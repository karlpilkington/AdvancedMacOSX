// webserve-thread.m -- a very simple web server using threads to 
//                      handle requests

/* compile with
cc -g -Wmost -o webserve-thread webserve-thread.m
*/

#import <sys/types.h>		// for pid_t, amongst others
#import <sys/wait.h>		// for wait3
#import <unistd.h>		// for fork
#import <stdlib.h>		// for EXIT_SUCCESS, pipe, exec
#import <stdio.h>		// for printf
#import <errno.h>		// for errno
#import <string.h>		// for strerror
#import <sys/time.h>		// for struct timeval
#import <sys/resource.h>	// for struct rusage
#import <netinet/in.h>  	// for sockaddr_in
#import <sys/socket.h>  	// for socket(), AF_INET
#import <arpa/inet.h>   	// for inet_ntoa
#import <unistd.h>      	// for close
#import <arpa/inet.h>   	// for inet_ntoa and friends
#import <assert.h>		// for assert
#import <pthread.h>		// for pthread_*

#define PORT_NUMBER 8080	// set to 80 to listen on the HTTP port
#define MAX_THREADS 5		// maximum number of connection threads


// ----- queue for handling requests

#define QUEUE_DEPTH 10

typedef struct Request {
    int			fd; // file descriptor of the incoming request
    struct sockaddr_in	address;
} Request;

static Request g_requestQueue[QUEUE_DEPTH];
static int g_queueEnd = -1; // 0 is the head.  end == -1 for empty queue
static pthread_mutex_t g_queueMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t g_queueCond = PTHREAD_COND_INITIALIZER;

void dumpQueue (void)
{
    int i;
    printf ("%d items in queue:\n", g_queueEnd + 1);

    for (i = 0; i <= g_queueEnd; i++) {
	printf ("%d:  fd is %d\n", i, g_requestQueue[i].fd);
    }
} // dumpQueue


void getRequest (int *fd, struct sockaddr_in *address)
{
    int doSignal = 0;

    printf ("before getRequest\n");
    dumpQueue ();

    pthread_mutex_lock (&g_queueMutex);
    while (g_queueEnd == -1) { // queue is empty
	pthread_cond_wait (&g_queueCond, &g_queueMutex);
    }

    printf ("after wakeup\n");
    dumpQueue ();

    // copy the request to the caller
    *fd = g_requestQueue[0].fd;
    memcpy (address, &g_requestQueue[0].address, sizeof(struct sockaddr_in));

    if (g_queueEnd == QUEUE_DEPTH - 1) {
	// going from full to not quite so full
	doSignal = 1;
    }

    // shift up the queue

    if (g_queueEnd > 0) {
	memmove (g_requestQueue, g_requestQueue + 1, 
		 sizeof(Request) * g_queueEnd);
    }
    g_queueEnd--;

    pthread_mutex_unlock (&g_queueMutex);

    if (doSignal) {
	pthread_cond_signal (&g_queueCond);
    }

} // getRequest


void queueRequest (int fd, struct sockaddr_in *address)
{
    pthread_mutex_lock (&g_queueMutex);

    assert (g_queueEnd <= QUEUE_DEPTH);

    printf ("before queue\n");
    while (g_queueEnd == QUEUE_DEPTH - 1) { // queue is full
	pthread_cond_wait (&g_queueCond, &g_queueMutex);
    }
    printf ("after queue\n");
    
    assert (g_queueEnd < QUEUE_DEPTH - 1);

    g_queueEnd++;
    g_requestQueue[g_queueEnd].fd = fd;
    memcpy (&g_requestQueue[g_queueEnd].address, address, 
	    sizeof(struct sockaddr_in));

    pthread_mutex_unlock (&g_queueMutex);

    pthread_cond_signal (&g_queueCond);

    printf ("enqueued another one\n");
    dumpQueue ();

} // queueRequest



// HTTP request handling

// these are some of the common HTTP response codes

#define HTTP_OK 	200
#define HTTP_NOT_FOUND	404
#define HTTP_ERROR	500


// return a string to the browser

#define returnString(httpResult, string, channel) \
	returnBuffer((httpResult), (string), (strlen(string)), (channel))

// return a character buffer (not necessarily zero-terminated) to the browser 
// (runs in the child)

void returnBuffer (int httpResult, const char *content, 
		   int contentLength, FILE *commChannel)
{
    fprintf (commChannel, "HTTP/1.0 %d blah\n", httpResult);
    fprintf (commChannel, "Content-Type: text/html\n");
    fprintf (commChannel, "Content-Length: %d\n", contentLength);
    fprintf (commChannel, "\n");
    fwrite (content, contentLength, 1, commChannel );

} // returnBuffer


// stream back to the browser numbers being counted, with a pause between
// them.  The user should see the numbers appear every couple of seconds
// (runs in the child)

void returnNumbers (int number, FILE *commChannel)
{
    int min, max, i;
    min = MIN (number, 1);
    max = MAX (number, 1);
    
    fprintf (commChannel, "HTTP/1.0 %d blah\n", HTTP_OK);
    fprintf (commChannel, "Content-Type: text/html\n");
    fprintf (commChannel, "\n"); // no content length since this is dynamic

    fprintf (commChannel, "<h2>The numbers from %d to %d</h2>\n", min, max);

    for (i = min; i <= max; i++) {
	sleep (2);
	fprintf (commChannel, "%d\n", i);
	fflush (commChannel);
    }

    fprintf (commChannel, "<hr>Done\n");

} // returnNumbers


// return a file from the file system, relative to where the webserve
// is running.  Note that this doesn't look for any nasty characters
// like '..', so this function is a pretty big security hole
// (runs in the child)

void returnFile (const char *filename, FILE *commChannel)
{
    FILE *file;
    const char *mimetype = NULL;

    // try to guess the mime type.  IE assumes all non-graphic files are HTML
    if (strstr(filename, ".m") != NULL) {
	mimetype = "text/plain";
    } else if (strstr(filename, ".h") != NULL) {
	mimetype = "text/plain";
    } else if (strstr(filename, ".txt") != NULL) {
	mimetype = "text/plain";
    } else if (strstr(filename, ".tgz") != NULL) {
	mimetype = "application/x-compressed";
    } else if (strstr(filename, ".html") != NULL) {
	mimetype = "text/html";
    } else if (strstr(filename, ".html") != NULL) {
	mimetype = "text/html";
    } else if (strstr(filename, ".xyz") != NULL) {
	mimetype = "audio/mpeg";
    }

    file = fopen (filename, "r");

    if (file == NULL) {
	returnString (HTTP_NOT_FOUND, "could not find your file.  Sorry\n.", 
		      commChannel);
    } else {
#define BUFFER_SIZE (8 * 1024)
	char *buffer[BUFFER_SIZE];
	int result;
	fprintf (commChannel, "HTTP/1.0 %d blah\n", HTTP_OK);
	if (mimetype != NULL) {
	    fprintf (commChannel, "Content-Type: %s\n", mimetype);
	}
	fprintf (commChannel, "\n");
	while ((result = fread (buffer, 1, BUFFER_SIZE, file)) > 0) {
	    fwrite (buffer, 1, result, commChannel);
	}
#undef BUFFER_SIZE
    }

} // returnFile


// using the method and the request (the path part of the url), generate the data
// for the user and send it back. (runs in the child)

void handleRequest (const char *method, const char *originalRequest, FILE *commChannel)
{
    char *request = strdup (originalRequest); // we'll use strsep to split this
    char *chunk, *nextString;

    if (strcmp(method, "GET") != 0) {
	returnString (HTTP_ERROR, "only GETs are supported", commChannel);
	goto bailout;
    }
    
    nextString = request;
    chunk = strsep (&nextString, "/"); 	// urls start with slashes, so chunk is ""
    chunk = strsep (&nextString, "/");  // the leading part of the url

    if (strcmp(chunk, "numbers") == 0) {
	int number;

	// url of the form /numbers/5 to print numbers from 1 to 5
	chunk = strsep (&nextString, "/");
	number = atoi(chunk);
	returnNumbers (number, commChannel);

    } else if (strcmp(chunk, "file") == 0) {
	chunk = strsep (&nextString, ""); // get the rest of the string
	returnFile (chunk, commChannel);
    } else {
	returnString (HTTP_NOT_FOUND, "could not handle your request.  Sorry\n.",
		      commChannel);
    }

bailout:
    fprintf (stderr, "child %ld handled request '%s'\n", 
	     (long)pthread_self(), originalRequest);

    free (request);

} // handleRequest



// read the request from the browser, pull apart the elements of the
// request, and then dispatch it.  (runs in the child)

void dispatchRequest (int fd, struct sockaddr_in *address)
{
#define LINEBUFFER_SIZE 8192
    char linebuffer[LINEBUFFER_SIZE];
    FILE *commChannel;

    commChannel = fdopen (fd, "r+");
    if (commChannel == NULL) {
	fprintf (stderr, "could not open commChannel.  Error is %d/%s\n",
		 errno, strerror(errno));
    }

    // this is pretty lame in that it only reads the first line and 
    // assumes that's the request, subsequently ignoring any headers
    // that might be sent.

    if (fgets(linebuffer, LINEBUFFER_SIZE, commChannel) != NULL) {
	// ok, now figure out what they wanted
	char *requestElements[3], *nextString, *chunk;
	int i = 0;
	nextString = linebuffer;
	while (chunk = strsep (&nextString, " ")) {
	    requestElements[i] = chunk;
	    i++;
	}
	if (i != 3) {
	    returnString (HTTP_ERROR, "malformed request", commChannel);
	    goto bailout;
	}
	
	handleRequest (requestElements[0], requestElements[1], commChannel);

    } else {
	fprintf (stderr, "read an empty request.  exiting\n");
    }

bailout:
    fclose (commChannel);

} // dispatchRequest




// sit blocking on accept until a new connection comes in.  queue the
// connection (which should eventually wake up a connection thread to
// handle it

void acceptRequest (int listenSocket)
{
    struct sockaddr_in address;
    socklen_t addressLength = sizeof(address);
    int result, fd;

    printf ("before accept\n");
    result = accept (listenSocket, (struct sockaddr *)&address, 
		     &addressLength);
    printf ("after accept\n");

    if (result == -1) {
	fprintf (stderr, "accept failed.  error: %d/%s\n",
		 errno, strerror(errno));
        goto bailout;
    }
    fd = result;

    queueRequest (fd, &address);

bailout:
    return;

} // acceptRequest


// ----- network stuff


// this is 100% stolen from chatterserver.m
// start listening on our server port (runs in parent)

int startListening ()
{
    int fd = -1, success = 0;
    int result;


    result = socket (AF_INET, SOCK_STREAM, 0);
    
    if (result == -1) {
        fprintf (stderr, "could not make a scoket.  error: %d / %s\n",
                 errno, strerror(errno));
        goto bailout;
    }
    fd = result;

    {
        int yes = 1;
        result = setsockopt (fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int));
        if (result == -1) {
            fprintf (stderr, "could not setsockopt to reuse address. %d / %s\n",
                     errno, strerror(errno));
            goto bailout;
        }
    }

    // bind to an address and port
    {
        struct sockaddr_in address;
        address.sin_len = sizeof (struct sockaddr_in);
        address.sin_family = AF_INET;
        address.sin_port = htons (PORT_NUMBER);
        address.sin_addr.s_addr = htonl (INADDR_ANY);
        memset (address.sin_zero, 0, sizeof(address.sin_zero));

        result = bind (fd, (struct sockaddr *)&address, sizeof(address));
        if (result == -1) {
            fprintf (stderr, "could not bind socket.  error: %d / %s\n",
                     errno, strerror(errno));
            goto bailout;
        }
    }
    
    result = listen (fd, 8);

    if (result == -1) {
        fprintf (stderr, "listen failed.  error: %d /  %s\n",
                 errno, strerror(errno));
        goto bailout;
    }

    success = 1;

bailout:
    if (!success) {
        close (fd);
        fd = -1;
    }
    return (fd);

} // startListening



// ----- thread functions

// there's just one of these. It's the producer of new requests

void *acceptThread (void *argument)
{
    int listenSocket = *((int *)argument);

    while (1) {
	acceptRequest (listenSocket);
    }

} // acceptThread


// there's N of these to handle requests

void *requestThread (void *argument)
{
    int fd;
    int result;

    // spin out on our own
    result = pthread_detach (pthread_self());

    if (result != 0) {
	fprintf (stderr, "could not detach connection thread.  error %d/%s\n",
		 result, strerror(result));
	return (NULL);
    }

    struct sockaddr_in address;

    while (1) {
	getRequest (&fd, &address); // this will block until request is queued
	dispatchRequest (fd, &address);
    }

} // requestThread


// ----- get things started in main

int main (int argc, char *argv[])
{
    int listenSocket, result;
    int i;
    pthread_t acceptThreadID;
    int status = EXIT_FAILURE;

    listenSocket = startListening ();

    if (listenSocket == -1) {
	fprintf (stderr, "startListening failed\n");
	goto bailout;
    }

    // block SIGPIPE so we don't croak if we try writing to a closed
    // connection
    if (signal (SIGPIPE, SIG_IGN) == SIG_ERR) {
	fprintf (stderr, "could not ignore SIGPIPE.  error is %d/%s\n",
		errno, strerror(errno));
	goto bailout;
    }
 

    // start our accept thread
    result = pthread_create (&acceptThreadID, NULL, acceptThread, 
			     &listenSocket);
    if (result != 0) {
	// pthread_* doesn't use errno :-|
	fprintf (stderr, "could not create accept thread.  error is %d/%s\n",
		 result, strerror(result));
	goto bailout;
    }

    // start our connection threads
    for (i = 0; i < MAX_THREADS; i++) {
	pthread_t connThreadID;
	result = pthread_create (&connThreadID, NULL, requestThread, NULL);
	if (result != 0) {
	    fprintf (stderr, "could not create connection thread.  "
		     "error is %d/%s\n", result, strerror(result));
	    goto bailout;
	}
    }

    pthread_join (acceptThreadID, NULL);

    status = EXIT_SUCCESS;
  bailout:
    return (status);

} // main



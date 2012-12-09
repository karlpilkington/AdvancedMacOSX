// append.m -- show an opening of a logfile, replacing a standard stream.
//

/* compile with:
gcc -g -Wall -o append append.m
*/

#import <errno.h>       // for errno and strerror
#import <fcntl.h>       // for OPEN
#import <stdio.h>       // for printf and friends
#import <stdlib.h>      // for EXIT_SUCCESS
#import <string.h>      // for strerror()
#import <unistd.h>      // for STDOUT_FILENO

int main (void) {
    close (STDOUT_FILENO);

    // open a log file, write only, and to always automatically append.
    // oh, and create the file if it doesn't exist already
    int fd = open ("/tmp/logthingie.txt", O_WRONLY | O_CREAT | O_APPEND,
                   S_IRUSR | S_IWUSR);
    if (fd == -1) {
        fprintf (stderr, "can't open log file.  Error %d (%s)\n",
                 errno, strerror(errno));
        exit (EXIT_FAILURE);
    }
    printf ("wheee, we have a log file open\n");

    exit (EXIT_SUCCESS);
    
} // main



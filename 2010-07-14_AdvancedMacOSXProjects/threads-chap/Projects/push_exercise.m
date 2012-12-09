// push_exercise.m - Serialization with mutexes.
//clang -g -std=c99 -Wall -Wextra -framework Foundation push_exercise.m -o push_exercise

#import <Foundation/Foundation.h>
#import <pthread.h> // pthread_*
#import <stdio.h>   // fprintf
#import <stdlib.h>  // EXIT_*
#import <string.h>  // strerror_r
#import <sys/time.h>  // setitimer

static NSMutableArray *gSharedArray;
static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;

void *push(void *);

int
main(void) {
    id pool = [[NSAutoreleasePool alloc] init];

    // Commit regularly scheduled suicide.
    struct itimerval fire = {
        {0,      0},  // interval
        {0, 250000}   // value
    };
    struct itimerval ofire;
    int err = setitimer(ITIMER_REAL, &fire, &ofire);
    if (err) perror("setitimer");

    gSharedArray = [[NSMutableArray alloc] init];

    pthread_t other;
    err = pthread_create(&other, NULL, push, NULL);
    if (err) perror("pthread_create");

    push(NULL);

    [pool drain];
    return EXIT_SUCCESS;
}

void *
push(void *unused __attribute__((__unused__))) {
    id pool = [[NSAutoreleasePool alloc] init];
    for (;;) {
        long r = random();
        NSNumber *n = [NSNumber numberWithLong:r];
        int err = pthread_mutex_lock(&m);

        if (err) {
            char buf[64];
            (void)strerror_r(err, buf, sizeof(buf));
            fprintf(stderr, "%s: *** pthread_mutex_lock: %s\n",
                    __func__, buf);
            continue;
        }

        NSLog(@"[%p] Adding %@.", (void *)pthread_self(), n);
        [gSharedArray addObject:n];

        err = pthread_mutex_unlock(&m);
        if (err) {
            char buf[64];
            (void)strerror_r(err, buf, sizeof(buf));
            fprintf(stderr, "%s: *** pthread_mutex_unlock: %s\n",
                    __func__, buf);
        }

    }
    [pool drain];
    return NULL;
}
// vi: set ts=4 sw=4 et filetype=objc syntax=objc:

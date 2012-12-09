// sleep_exercise.m - Use a timer source.
//clang -g -std=c99 -Wall -Wextra sleep_exercise.m -o sleep_exercise

#import <dispatch/dispatch.h>
#import <inttypes.h>  // PRI*
#import <stdio.h>     // fprintf
#import <stdlib.h>    // EXIT_*

void sleep_ns(uint64_t nanos);

int
main(void) {
    uint64_t naptime = 5ull * NSEC_PER_SEC;
    fprintf(stderr, "Sleeping %"PRIu64" nanos.\n", naptime);
    sleep_ns(naptime);
    fputs("::yawn:: Awake already?\n", stderr);
    return EXIT_SUCCESS;
}

void
sleep_ns(uint64_t nanos) {
    if (0ULL == nanos) return;

    // Create a semaphore to block on.
    dispatch_semaphore_t sema = dispatch_semaphore_create(0L);

    // Create a timer source to unblock us.
    const long prio = DISPATCH_QUEUE_PRIORITY_DEFAULT;
    dispatch_queue_t q = dispatch_get_global_queue(prio, 0UL);

    dispatch_source_type_t type = DISPATCH_SOURCE_TYPE_TIMER;
    dispatch_source_t timer = dispatch_source_create(type, 0UL, 0UL, q);

    dispatch_source_set_event_handler(timer, ^{
        dispatch_source_cancel(timer);
        dispatch_release(timer);
        (void)dispatch_semaphore_signal(sema);
    });

    const dispatch_time_t when = dispatch_time(DISPATCH_TIME_NOW, nanos);
    dispatch_source_set_timer(timer, when, 0ULL/*interval*/, 0ULL/*leeway*/);
    dispatch_resume(timer);

    // Block.
    (void)dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    dispatch_release(sema), sema = NULL;
}

// vi: set ts=4 sw=4 et filetype=objc syntax=objc:

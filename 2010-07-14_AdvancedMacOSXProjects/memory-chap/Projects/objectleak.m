// objectleak.m -- Leak some Cocoa objects

//gcc -Wmost -g -framework Foundation -o objectleak objectleak.m

#import <Foundation/Foundation.h>

int main (void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSMutableArray *array = [[NSMutableArray alloc] init];
    int i;
    for (i = 0; i < 20; i++) {
	NSNumber *number =
            [[NSNumber alloc] initWithInt: i]; // retain count of 1
	[number retain];
	[array addObject: number]; // number has retain count of 2
    }

    [array release]; // Each of the numbers have retain counts of 1.
    // Therefore we've leaked each of the numbers

    [pool drain];
    sleep (5000);
    // Now would be a good time to run leaks.
    exit (0);

} // main

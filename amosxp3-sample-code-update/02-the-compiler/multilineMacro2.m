#import <stdio.h>

#define FOUND_AN_ERROR(desc)   \
    do {   \
        error_count++;   \
        fprintf(stderr, "found an error '%s' at file %s, line %d\n",  \
                desc, __FILE__, __LINE__) \
    } while (0)

int error_count;

int main (int argc, char *argv[])
{
    if (argc == 2)
	FOUND_AN_ERROR ("something really bad happened");
    printf ("done\n");

} // main

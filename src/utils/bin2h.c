#include <stdio.h>
#include <stdlib.h>

int main( int argc, char *argv[] )
{
    char var_name[30] = "cfgware";
    FILE *fpIn = NULL, *fpOut = NULL;
    unsigned char buffer[5], i;
    printf( "argc: %d\n", argc );

    if ( argc == 4 )
    {
        fpIn = fopen( argv[1], "rb" );
        fpOut = fopen( argv[2], "wt" );
        sprintf( var_name, "%s", argv[3] );
    }
    else if ( argc == 3 )
    {
        fpIn = fopen( argv[1], "rb" );
        fpOut = fopen( argv[2], "wt" );
    }
    else if ( argc == 2 )
    {
        fpIn = fopen( argv[1], "rb" );
        fpOut = stdout;
    }
    else if ( argc == 1 )
    {
        fpIn = stdin;
        fpOut = stdout;
    }
    else
    {
        fprintf( stderr, "usage: %s [infile] [outfile] [name]\n", argv[0] );
        return -1;
    }

    //   if (argc > 1)
    //      sprintf()

    if ( fpIn == NULL )
    {
        fprintf( stderr, "Can't open '%s`: Aborting.", argv[1] );
        return -1;
    }

    if ( fpOut == NULL )
    {
        fprintf( stderr, "Can't open '%s`: Aborting.", argv[2] );
        return -1;
    }

    fprintf( fpOut, "const uint8_t %s[] = {\n", var_name );
    i = 0;

    while ( !feof( fpIn ) )
    {
        fread( buffer, 1, 1, fpIn );
        fprintf( fpOut, "0x%02X, ", buffer[0] );
        i++;

        if ( i > 8 )
        {
            fprintf( fpOut, "\n" );
            i = 0;
        }
    }

    if ( i > 0 )
    {
        fprintf( fpOut, "\n" );
    }

    fprintf( fpOut, "};" );
    fclose( fpOut ); fclose( fpIn );
    return 0;
}

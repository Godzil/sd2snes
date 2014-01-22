#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include "cfgware.h"

int main( int argc, char *argv[] )
{
    int i;

    for ( i = 0; i < sizeof( cfgware ); i++ )
    {
        printf( "%c", cfgware[i] );
    }

    return 0;
}

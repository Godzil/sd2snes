
CC = gcc
CFLAGS = -Wall -Wstrict-prototypes -Werror

all: lpcchksum genhdr bin2h

genhdr: genhdr.o
	$(CC) $(CFLAGS) $^ --output $@

bin2h: bin2h.o
	$(CC) $(CFLAGS) $^ --output $@

lpcchksum: lpcchksum.o
	$(CC) $(CFLAGS) $^ --output $@

%.o: %.c
	$(CC) -c $(CFLAGS) $< -o $@


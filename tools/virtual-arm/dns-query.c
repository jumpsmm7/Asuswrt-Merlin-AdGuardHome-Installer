/* Native DNS assertions for isolated virtual ARM guests; no libc DNS shortcuts. */
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#define PACKET_SIZE 4096
#define NAME_SIZE 256

static void fail(const char *message)
{
	fprintf(stderr, "DNS assertion failed: %s\n", message);
	exit(1);
}

static uint16_t get16(const unsigned char *bytes)
{
	return (uint16_t)((unsigned int)bytes[0] * 256U + bytes[1]);
}

static void put16(unsigned char *bytes, uint16_t value)
{
	bytes[0] = (unsigned char)(value >> 8);
	bytes[1] = (unsigned char)(value & 255U);
}

/* Bound pointer traversal and wire consumption separately for compressed names. */
static size_t read_name(const unsigned char *packet, size_t length, size_t offset,
	char *name)
{
	size_t used = 0, written = 0, steps = 0;
	int jumped = 0;
	for (;;) {
		unsigned int label;
		if (offset >= length || ++steps > length)
			fail("invalid or looping compressed name");
		label = packet[offset++];
		if (!jumped)
			used++;
		if (label == 0)
			break;
		if ((label & 192U) == 192U) {
			if (offset >= length)
				fail("truncated compression pointer");
			if (!jumped)
				used++;
			offset = (size_t)((label & 63U) * 256U + packet[offset]);
			jumped = 1;
			continue;
		}
		if (label > 63 || offset + label > length || written + label + 1 >= NAME_SIZE)
			fail("invalid DNS label");
		if (written)
			name[written++] = '.';
		memcpy(name + written, packet + offset, label);
		written += label;
		offset += label;
		if (!jumped)
			used += label;
	}
	name[written] = '\0';
	return used;
}

static size_t write_name(unsigned char *packet, const char *name)
{
	size_t written = 0;
	const char *cursor = name;
	while (*cursor) {
		const char *dot = strchr(cursor, '.');
		size_t length = dot ? (size_t)(dot - cursor) : strlen(cursor);
		if (length == 0 || length > 63 || written + length + 2 > NAME_SIZE)
			fail("invalid query name");
		packet[written++] = (unsigned char)length;
		memcpy(packet + written, cursor, length);
		written += length;
		if (!dot)
			break;
		cursor = dot + 1;
	}
	packet[written++] = 0;
	return written;
}

static void transfer(int fd, unsigned char *bytes, size_t length, int writing)
{
	while (length) {
		ssize_t count = writing ? send(fd, bytes, length, 0) : recv(fd, bytes, length, 0);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			fail(writing ? "TCP send failed" : "TCP receive failed");
		bytes += (size_t)count;
		length -= (size_t)count;
	}
}

/* hold owns real TCP and UDP sockets so startup refusal can preserve its PID. */
static void hold(const struct addrinfo *address)
{
	int udp = socket(address->ai_family, SOCK_DGRAM, 0);
	int tcp = socket(address->ai_family, SOCK_STREAM, 0);
	if (udp < 0 || tcp < 0 || bind(udp, address->ai_addr, address->ai_addrlen) != 0 ||
		bind(tcp, address->ai_addr, address->ai_addrlen) != 0 || listen(tcp, 1) != 0)
		fail("foreign-owner socket bind failed");
	puts("READY: foreign TCP/UDP DNS owner");
	fflush(stdout);
	for (;;)
		pause();
}

int main(int argc, char **argv)
{
	struct addrinfo hints, *address;
	struct timeval timeout = { 3, 0 };
	struct timespec now;
	unsigned char query[PACKET_SIZE] = { 0 }, reply[PACKET_SIZE], prefix[2];
	char query_name[NAME_SIZE], answer_name[NAME_SIZE], actual[INET6_ADDRSTRLEN];
	uint16_t id, type;
	size_t query_length, reply_length, offset, name_length;
	unsigned int answer, answers, records;
	int fd, tcp, matched = 0;
	if (argc != 7 && !(argc == 4 && strcmp(argv[3], "hold") == 0))
		fail("usage: agh-dns-query server port udp|tcp A|PTR|AAAA name expected; or server port hold");
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_DGRAM;
	hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV;
	if (getaddrinfo(argv[1], argv[2], &hints, &address) != 0)
		fail("server and port must be numeric");
	if (argc == 4)
		hold(address);
	if (strcmp(argv[3], "tcp") == 0)
		tcp = 1;
	else if (strcmp(argv[3], "udp") == 0)
		tcp = 0;
	else
		fail("transport must be udp or tcp");
	if (strcmp(argv[4], "A") == 0)
		type = 1;
	else if (strcmp(argv[4], "PTR") == 0)
		type = 12;
	else if (strcmp(argv[4], "AAAA") == 0)
		type = 28;
	else
		fail("query type must be A, PTR or AAAA");
	if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
		fail("monotonic clock unavailable");
	id = (uint16_t)((unsigned long)getpid() ^ (unsigned long)now.tv_nsec);
	put16(query, id);
	put16(query + 2, 256);
	put16(query + 4, 1);
	query_length = 12 + write_name(query + 12, argv[5]);
	put16(query + query_length, type);
	put16(query + query_length + 2, 1);
	query_length += 4;
	(void)read_name(query, query_length, 12, query_name);
	fd = socket(address->ai_family, tcp ? SOCK_STREAM : SOCK_DGRAM, 0);
	if (fd < 0 || setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) != 0 ||
		setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) != 0)
		fail("could not configure DNS socket");
	alarm(8);
	if (connect(fd, address->ai_addr, address->ai_addrlen) != 0)
		fail("DNS connect failed");
	freeaddrinfo(address);
	if (tcp) {
		put16(prefix, (uint16_t)query_length);
		transfer(fd, prefix, 2, 1);
		transfer(fd, query, query_length, 1);
		transfer(fd, prefix, 2, 0);
		reply_length = get16(prefix);
		if (reply_length > PACKET_SIZE)
			fail("oversized TCP DNS response");
		transfer(fd, reply, reply_length, 0);
	} else {
		ssize_t count;
		if (send(fd, query, query_length, 0) != (ssize_t)query_length)
			fail("UDP DNS send failed");
		count = recv(fd, reply, sizeof(reply), MSG_TRUNC);
		if (count < 0 || count > PACKET_SIZE)
			fail("UDP DNS receive failed or truncated datagram");
		reply_length = (size_t)count;
	}
	close(fd);
	alarm(0);
	if (reply_length < 12 || get16(reply) != id || (get16(reply + 2) & 0xf80fU) != 0x8000U ||
		(get16(reply + 2) & 0x0200U) != 0 || get16(reply + 4) != 1)
		fail("invalid response identity, opcode, status, truncation or question count");
	offset = 12 + read_name(reply, reply_length, 12, answer_name);
	if (offset + 4 > reply_length || strcmp(answer_name, query_name) != 0 ||
		get16(reply + offset) != type || get16(reply + offset + 2) != 1)
		fail("response question differs from request");
	offset += 4;
	answers = get16(reply + 6);
	/* Every declared section must fit, even after a matching answer. */
	records = answers + get16(reply + 8) + get16(reply + 10);
	for (answer = 0; answer < records; answer++) {
		uint16_t answer_type, answer_class, data_length;
		name_length = read_name(reply, reply_length, offset, answer_name);
		offset += name_length;
		if (offset + 10 > reply_length)
			fail("truncated DNS record header");
		answer_type = get16(reply + offset);
		answer_class = get16(reply + offset + 2);
		data_length = get16(reply + offset + 8);
		offset += 10;
		if (offset + data_length > reply_length)
			fail("truncated DNS record data");
		if (answer < answers && answer_type == type && answer_class == 1 && strcmp(answer_name, query_name) == 0) {
			if (type == 12) {
				if (read_name(reply, reply_length, offset, answer_name) != data_length)
					fail("PTR data length differs from compressed name");
				if (strcmp(answer_name, argv[6]) == 0)
					matched = 1;
			} else {
				int family = type == 1 ? AF_INET : AF_INET6;
				unsigned char expected[16];
				size_t wanted = type == 1 ? 4 : 16;
				if (data_length != wanted || inet_pton(family, argv[6], expected) != 1)
					fail("invalid address answer or expectation");
				if (!inet_ntop(family, reply + offset, actual, sizeof(actual)))
					fail("could not format address answer");
				if (memcmp(reply + offset, expected, wanted) == 0)
					matched = 1;
			}
		}
		offset += data_length;
	}
	if (!matched)
		fail("expected exact answer was absent");
	printf("PASS: DNS %s %s server=%s:%s name=%s answer=%s\n",
		argv[3], argv[4], argv[1], argv[2], argv[5], argv[6]);
	return 0;
}

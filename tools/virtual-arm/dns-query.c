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

struct dns_query {
	unsigned char bytes[PACKET_SIZE];
	size_t length;
	uint16_t id;
	uint16_t type;
	char name[NAME_SIZE];
};

struct dns_record {
	char name[NAME_SIZE];
	uint16_t type;
	uint16_t class;
	uint16_t data_length;
	size_t data_offset;
};

/** Report an assertion failure to stderr and terminate with a failing status. */
static void fail(const char *message)
{
	fprintf(stderr, "DNS assertion failed: %s\n", message);
	exit(1);
}

/** Decode two readable DNS wire bytes as an unsigned network-order value. */
static uint16_t get16(const unsigned char *bytes)
{
	return (uint16_t)((unsigned int)bytes[0] * 256U + bytes[1]);
}

/** Encode an unsigned value into two writable DNS wire bytes in network order. */
static void put16(unsigned char *bytes, uint16_t value)
{
	bytes[0] = (unsigned char)(value >> 8);
	bytes[1] = (unsigned char)(value & 255U);
}

/** Decode a complete compression pointer and require every hop to be backward. */
static size_t pointer_target(const unsigned char *packet, size_t length,
	size_t label_start, size_t offset, unsigned int label)
{
	size_t target;
	if (offset >= length)
		fail("truncated compression pointer");
	target = (size_t)((label & 63U) * 256U + packet[offset]);
	if (target >= label_start)
		fail("compression pointer does not refer backwards");
	return target;
}

/**
 * Decode a bounded DNS name into the caller's NAME_SIZE buffer.
 * Return bytes consumed at the original offset, independently of pointer
 * traversal, and fail on malformed labels or a non-backward compression hop.
 */
static size_t read_name(const unsigned char *packet, size_t length, size_t offset,
	char *name)
{
	size_t used = 0;
	size_t written = 0;
	size_t steps = 0;
	int jumped = 0;
	for (;;) {
		size_t label_start = offset;
		unsigned int label;
		steps++;
		if (offset >= length || steps > length)
			fail("invalid or looping compressed name");
		label = packet[offset++];
		if (!jumped)
			used++;
		if (label == 0)
			break;
		if ((label & 192U) == 192U) {
			if (!jumped)
				used++;
			offset = pointer_target(packet, length, label_start, offset, label);
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

/**
 * Encode a dotted query name into a caller-provided NAME_SIZE wire buffer.
 * Return its encoded size, including the terminating root label, or fail when
 * a label or the complete encoded name exceeds the supported bounds.
 */
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

/**
 * Send or receive exactly length TCP bytes, retrying interrupted operations.
 * Fail on a socket error or early EOF instead of accepting a partial frame.
 */
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

/**
 * Bind real TCP and UDP sockets to the resolved address, announce readiness,
 * and retain ownership until terminated so startup tests can verify its PID.
 */
static void hold(const struct addrinfo *address)
{
	int udp = socket(address->ai_family, SOCK_DGRAM, 0);
	int tcp = socket(address->ai_family, SOCK_STREAM, 0);
	if (udp < 0 || tcp < 0)
		fail("foreign-owner socket bind failed");
	if (bind(udp, address->ai_addr, address->ai_addrlen) != 0)
		fail("foreign-owner socket bind failed");
	if (bind(tcp, address->ai_addr, address->ai_addrlen) != 0)
		fail("foreign-owner socket bind failed");
	if (listen(tcp, 1) != 0)
		fail("foreign-owner socket bind failed");
	puts("READY: foreign TCP/UDP DNS owner");
	fflush(stdout);
	for (;;)
		pause();
}

/** Resolve only numeric server and service arguments without libc DNS lookup. */
static struct addrinfo *server_address(const char *server, const char *port)
{
	struct addrinfo hints;
	struct addrinfo *address;
	memset(&hints, 0, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_DGRAM;
	hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV;
	if (getaddrinfo(server, port, &hints, &address) != 0)
		fail("server and port must be numeric");
	return address;
}

/** Map the explicitly supported transport to its socket mode or fail. */
static int query_transport(const char *transport)
{
	if (strcmp(transport, "tcp") == 0)
		return 1;
	if (strcmp(transport, "udp") != 0)
		fail("transport must be udp or tcp");
	return 0;
}

/** Map one supported DNS record spelling to its wire type or fail. */
static uint16_t query_type(const char *kind)
{
	if (strcmp(kind, "A") == 0)
		return 1;
	if (strcmp(kind, "PTR") == 0)
		return 12;
	if (strcmp(kind, "AAAA") != 0)
		fail("query type must be A, PTR or AAAA");
	return 28;
}

/** Prepare one bounded IN-class query and retain its canonical decoded name. */
static void prepare_query(struct dns_query *query, uint16_t type, const char *name)
{
	struct timespec now;
	if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
		fail("monotonic clock unavailable");
	query->type = type;
	query->id = (uint16_t)((unsigned long)getpid() ^ (unsigned long)now.tv_nsec);
	put16(query->bytes, query->id);
	put16(query->bytes + 2, 256);
	put16(query->bytes + 4, 1);
	query->length = 12 + write_name(query->bytes + 12, name);
	put16(query->bytes + query->length, type);
	put16(query->bytes + query->length + 2, 1);
	query->length += 4;
	(void)read_name(query->bytes, query->length, 12, query->name);
}

/** Open the requested DNS socket with bounded send and receive operations. */
static int query_socket(const struct addrinfo *address, int tcp)
{
	struct timeval timeout = { 3, 0 };
	int fd = socket(address->ai_family, tcp ? SOCK_STREAM : SOCK_DGRAM, 0);
	if (fd < 0)
		fail("could not configure DNS socket");
	if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) != 0)
		fail("could not configure DNS socket");
	if (setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) != 0)
		fail("could not configure DNS socket");
	return fd;
}

/** Exchange a complete length-prefixed TCP query and reject oversized frames. */
static size_t tcp_response(int fd, struct dns_query *query, unsigned char *reply)
{
	unsigned char prefix[2];
	size_t length;
	put16(prefix, (uint16_t)query->length);
	transfer(fd, prefix, 2, 1);
	transfer(fd, query->bytes, query->length, 1);
	transfer(fd, prefix, 2, 0);
	length = get16(prefix);
	if (length > PACKET_SIZE)
		fail("oversized TCP DNS response");
	transfer(fd, reply, length, 0);
	return length;
}

/** Exchange one UDP datagram and reject socket errors or truncated messages. */
static size_t udp_response(int fd, const struct dns_query *query, unsigned char *reply)
{
	ssize_t count;
	if (send(fd, query->bytes, query->length, 0) != (ssize_t)query->length)
		fail("UDP DNS send failed");
	count = recv(fd, reply, PACKET_SIZE, MSG_TRUNC);
	if (count < 0 || count > PACKET_SIZE)
		fail("UDP DNS receive failed or truncated datagram");
	return (size_t)count;
}

/** Bound the complete socket exchange and release the descriptor afterward. */
static size_t exchange(struct addrinfo *address, struct dns_query *query, int tcp,
	unsigned char *reply)
{
	int fd = query_socket(address, tcp);
	size_t length;
	alarm(8);
	if (connect(fd, address->ai_addr, address->ai_addrlen) != 0)
		fail("DNS connect failed");
	freeaddrinfo(address);
	length = tcp ? tcp_response(fd, query, reply) : udp_response(fd, query, reply);
	close(fd);
	alarm(0);
	return length;
}

/** Validate response identity and its sole question before inspecting records. */
static size_t response_question(const unsigned char *reply, size_t length,
	const struct dns_query *query)
{
	char name[NAME_SIZE];
	size_t offset;
	if (length < 12 || get16(reply) != query->id || (get16(reply + 2) & 0xf80fU) != 0x8000U ||
		(get16(reply + 2) & 0x0200U) != 0 || get16(reply + 4) != 1)
		fail("invalid response identity, opcode, status, truncation or question count");
	offset = 12 + read_name(reply, length, 12, name);
	if (offset + 4 > length || strcmp(name, query->name) != 0 ||
		get16(reply + offset) != query->type || get16(reply + offset + 2) != 1)
		fail("response question differs from request");
	return offset + 4;
}

/** Decode one bounded resource record and advance through its complete data. */
static void read_record(const unsigned char *reply, size_t length, size_t *offset,
	struct dns_record *record)
{
	*offset += read_name(reply, length, *offset, record->name);
	if (*offset + 10 > length)
		fail("truncated DNS record header");
	record->type = get16(reply + *offset);
	record->class = get16(reply + *offset + 2);
	record->data_length = get16(reply + *offset + 8);
	*offset += 10;
	record->data_offset = *offset;
	if (*offset + record->data_length > length)
		fail("truncated DNS record data");
	*offset += record->data_length;
}

/** Compare an address RDATA value to a valid numeric expectation of its type. */
static int address_matches(const unsigned char *data, const struct dns_record *record,
	const char *expectation)
{
	int family = record->type == 1 ? AF_INET : AF_INET6;
	size_t wanted = record->type == 1 ? 4 : 16;
	unsigned char expected[16];
	char actual[INET6_ADDRSTRLEN];
	if (record->data_length != wanted || inet_pton(family, expectation, expected) != 1)
		fail("invalid address answer or expectation");
	if (!inet_ntop(family, data, actual, sizeof(actual)))
		fail("could not format address answer");
	return memcmp(data, expected, wanted) == 0;
}

/** Match only IN-class records for this query, validating complete PTR RDATA. */
static int record_matches(const unsigned char *reply, size_t length,
	const struct dns_record *record, const struct dns_query *query, const char *expected)
{
	char name[NAME_SIZE];
	if (record->type != query->type || record->class != 1 || strcmp(record->name, query->name) != 0)
		return 0;
	if (query->type != 12)
		return address_matches(reply + record->data_offset, record, expected);
	if (read_name(reply, length, record->data_offset, name) != record->data_length)
		fail("PTR data length differs from compressed name");
	return strcmp(name, expected) == 0;
}

/** Require one exact answer while validating every declared DNS record section. */
static void validate_response(const unsigned char *reply, size_t length,
	const struct dns_query *query, const char *expected)
{
	size_t offset = response_question(reply, length, query);
	unsigned int answers = get16(reply + 6);
	unsigned int records = answers + get16(reply + 8) + get16(reply + 10);
	int matched = 0;
	/* Every declared section must fit, even after a matching answer. */
	for (unsigned int answer = 0; answer < records; answer++) {
		struct dns_record record;
		read_record(reply, length, &offset, &record);
		if (answer >= answers)
			continue;
		if (record_matches(reply, length, &record, query, expected))
			matched = 1;
	}
	if (!matched)
		fail("expected exact answer was absent");
}

/**
 * Run a numeric-address UDP/TCP DNS assertion or hold foreign-owner sockets.
 * Query mode validates every declared record and requires an exact A, AAAA or
 * PTR answer; malformed input, transport failure or a missing answer fails.
 */
int main(int argc, char **argv)
{
	struct addrinfo *address;
	struct dns_query query = { { 0 }, 0, 0, 0, { 0 } };
	unsigned char reply[PACKET_SIZE];
	size_t length;
	int tcp;
	if (argc != 7 && !(argc == 4 && strcmp(argv[3], "hold") == 0))
		fail("usage: agh-dns-query server port udp|tcp A|PTR|AAAA name expected; or server port hold");
	address = server_address(argv[1], argv[2]);
	if (argc == 4)
		hold(address);
	tcp = query_transport(argv[3]);
	prepare_query(&query, query_type(argv[4]), argv[5]);
	length = exchange(address, &query, tcp, reply);
	validate_response(reply, length, &query, argv[6]);
	printf("PASS: DNS %s %s server=%s:%s name=%s answer=%s\n",
		argv[3], argv[4], argv[1], argv[2], argv[5], argv[6]);
	return 0;
}

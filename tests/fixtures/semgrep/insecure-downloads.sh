#!/bin/sh
curl -k https://example.invalid/a
curl --insecure https://example.invalid/b
curl -kL https://example.invalid/c
curl -fsSk https://example.invalid/d
wget --no-check-certificate https://example.invalid/e

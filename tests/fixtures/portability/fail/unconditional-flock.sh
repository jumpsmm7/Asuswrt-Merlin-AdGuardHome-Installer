#!/bin/sh
exec 8>lock
flock 8

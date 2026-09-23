#!/usr/bin/env python3
# Copyright (c) 2026 ravindu644 <droidcasts@protonmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Make a boot image acceptable to newer Wingtech/Samsung bootloaders
# (SM-T295 "SECURE CHECK FAIL: boot.img").
#
# The bootloader expects a 512-byte block starting with "SignerVer02" right
# after "SEANDROIDENFORCE", and locates it as the last 512 bytes of the AVB
# footer's original_image_size. Magisk drops the block; APatch keeps it but
# points the footer past it. This fixes both.
#
#   fix_samsung_boot.py IN.img            fix in place
#   fix_samsung_boot.py IN.img OUT.img    fix into a new file
#   fix_samsung_boot.py IN.img OUT.tar    fix a copy and pack it as boot.img
import os
import sys
import tarfile
import tempfile

if len(sys.argv) not in (2, 3):
    sys.exit(__doc__ or 'usage: fix_samsung_boot.py IN.img [OUT.img|OUT.tar]')
src = sys.argv[1]
dst = sys.argv[2] if len(sys.argv) == 3 else src

d = bytearray(open(src, 'rb').read())
if d[:8] != b'ANDROID!':
    sys.exit(f'{src}: not an Android boot image')
if d[-64:-60] != b'AVBf':
    sys.exit(f'{src}: no AVB footer, cannot locate the Samsung block')

n = int.from_bytes(d[-52:-44], 'big')       # footer original_image_size
sv = d.find(b'SignerVer02')
if sv < 0:
    if d[n:n + 16] == b'SEANDROIDENFORCE':
        n += 16
    if d[n:n + 512] != bytes(512):
        sys.exit(f'{src}: no room for the SignerVer02 block at {n}')
    d[n:n + 11] = b'SignerVer02'
    sv = n
    print(f'inserted SignerVer02 at {sv}')
want = sv + 512
if int.from_bytes(d[-52:-44], 'big') == want:
    print(f'{src}: already correct')
else:
    d[-52:-44] = want.to_bytes(8, 'big')
    print(f'footer original_image_size -> {want}')

if dst.endswith('.tar'):
    with tempfile.TemporaryDirectory() as t:
        img = os.path.join(t, 'boot.img')
        open(img, 'wb').write(d)
        with tarfile.open(dst, 'w', format=tarfile.USTAR_FORMAT) as tar:
            tar.add(img, arcname='boot.img')
else:
    open(dst, 'wb').write(d)
print(f'wrote {dst}')

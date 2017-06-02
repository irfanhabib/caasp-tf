#!/bin/sh
#
# Author(s): Alvaro Saurin <alvaro.saurin@suse.com>
#
# Copyright (c) 2017 SUSE LINUX GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.
#

# get the IP of one of the VMs from the Terraform state file

if [ $# -gt 0 ] ; then
	terraform output -json nodes | \
		python -c "import sys, json; print json.load(sys.stdin)['value'][$1]"
else
	terraform output -json nodes | \
		python -c "import sys, json; print ' '.join(json.load(sys.stdin)['value'])"
fi

#!/usr/bin/python
# encoding: utf-8
"""
test_processinstall.py

Unit tests for munkicommon's processInstall function.

"""
# Copyright 2016-present Nate Walck.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


import code.client.munkilib.updatecheck as updatecheck
import unittest
from scaffolds import updatecheck as scaffolds

try:
    from mock import patch
except ImportError:
    import sys
    print >>sys.stderr, "mock module is required. run: easy_install mock"
    raise

# ToDo
# Mock manifestiem
# Mock cataloglist
# Mock installinfo


class TestProcessInstall(unittest.TestCase):
    """Test munkicommon.processInstall"""

    def setUp(self):
        self.cataloglist = scaffolds.cataloglist()
        self.installinfo = scaffolds.installinfo()
        return

    def tearDown(self):
        return

    def test_already_processed_install(self):
        print("processInstall for an already processed install item...")
        self.installinfo['processed_installs'].append('Firefox')
        processinstall_result = updatecheck.processInstall(
            u'Firefox',
            self.cataloglist,
            self.installinfo
        )
        self.assertEqual(processinstall_result, True)

    def test_already_processed_uninstall(self):
        print("processInstall for an already processed uninstall item...")
        self.installinfo['processed_uninstalls'].append('Firefox')
        processinstall_result = updatecheck.processInstall(
            u'Firefox',
            self.cataloglist,
            self.installinfo
        )
        self.assertEqual(processinstall_result, False)

    def test_no_pkginfo_found_in_catalogs(self):
        # This needs to be mocked out some more. It doesn't actually have a scaffold catalog
        print("processInstall for an item not in the catalogs...")
        processinstall_result = updatecheck.processInstall(
            u'DoesNotExist',
            self.cataloglist,
            self.installinfo
        )
        self.assertEqual(processinstall_result, False)

    def test_is_or_will_be_installed(self):
        pass

    def test_could_not_resolve_dependancies(self):
        pass

    def test_recursive_processinstall_call(self):
        pass

    def test_fetch_verification_error(self):
        pass

    def test_fetch_gurl_download_error(self):
        pass

    def test_fetch_munki_download_error(self):
        pass

    def test_item_already_installed(self):
        # Probably needs multiple tests as it can stuff stuff into installinfo for dependancies and other conditions
        pass
    # def test_manifest_name_split(self):
        # print("Testing processInstall...")
        # pass


def main():
    unittest.main(buffer=True)


if __name__ == '__main__':
    main()

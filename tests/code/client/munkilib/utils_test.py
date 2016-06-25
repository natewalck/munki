#!/usr/bin/python
# encoding: utf-8
"""
utils_test.py

Unit tests for munkilib's util functions.

"""
# Copyright 2016 Nate Walck
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


import utils
import sys
import unittest
import mock


class utilsTest(unittest.TestCase):

    def setUp(self):
        print("Setting up utils tests...")

    def tearDown(self):
        print("Tearing down after utils tests...")

    def test_file_permissions_when_correct(self):
        print("Testing correct file permissions")
        # ToDo
        # 1. Mock input file for utils.verifyFileOnlyWritableByMunkiAndRoot
        # 2. mock the stat restuls
        # 3. Patch os.stat so it returns the mocked stat result
        mocked_stat = mock.Mock()
        mocked_stat.st_uid = 80
        mock_os_stat = mock.MagicMock()
        mock_os_stat = mocked_stat
        mock.patch('utils.os.stat', mock_os_stat)
        utils.verifyFileOnlyWritableByMunkiAndRoot('/tmp/test')

    def test_file_permissions_when_incorrect(self):
        print("Testing incorrect file permissions")


if __name__ == "__main__":
    unittest.main()

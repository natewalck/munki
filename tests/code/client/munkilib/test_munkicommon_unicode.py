#!/usr/bin/python
# encoding: utf-8
"""
munkicommon_display_unicode_test.py

Unit tests for munkicommon's display_* functions.

"""
# Copyright 2014-2016 Greg Neagle.
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


import code.client.munkilib.munkicommon as munkicommon
import sys
import unittest
from StringIO import StringIO
from mock import patch

MSG_UNI = u'Günther\'s favorite thing is %s'
MSG_STR = 'Günther\'s favorite thing is %s'

ARG_UNI = u'Günther'
ARG_STR = 'Günther'

RESULT_STR = 'Günther\'s favorite thing is %s' % ARG_STR

def log(msg, logname=''):
    """Redefine munkicommon's logging function so our tests don't write
    a bunch of garbage to Munki's logs"""
    pass
munkicommon.log = log


class TestDisplayInfoUnicodeOutput(unittest.TestCase):
    """Test munkicommon display_info with text that may or may not be proper 
    Unicode."""

    @patch('sys.stdout', new_callable=StringIO)
    def test_display_info_with_unicode_msg(self, mock_stdout):
        munkicommon.display_info(MSG_UNI)
        self.assertEqual(MSG_STR,
            mock_stdout.getvalue().strip()
        )

    @patch('sys.stdout', new_callable=StringIO)
    def test_display_info_with_str_msg(self, mock_stdout):
        munkicommon.display_info(MSG_STR)
        self.assertEqual(MSG_STR,
            mock_stdout.getvalue().strip()
        )

    @patch('sys.stdout', new_callable=StringIO)
    def test_display_info_with_unicode_msg_unicode_arg(self, mock_stdout):
        munkicommon.display_info(MSG_UNI, ARG_UNI)
        self.assertEqual(RESULT_STR,
            mock_stdout.getvalue().strip()
        )

    @patch('sys.stdout', new_callable=StringIO)
    def test_display_info_with_unicode_msg_str_arg(self, mock_stdout):
        munkicommon.display_info(MSG_UNI, ARG_STR)
        self.assertEqual(RESULT_STR,
            mock_stdout.getvalue().strip()
        )

    @patch('sys.stdout', new_callable=StringIO)
    def test_display_info_with_str_msg_unicode_arg(self, mock_stdout):
        munkicommon.display_info(MSG_STR, ARG_UNI)
        self.assertEqual(RESULT_STR,
            mock_stdout.getvalue().strip()
        )

    @patch('sys.stdout', new_callable=StringIO)
    def test_display_info_with_str_msg_str_arg(self, mock_stdout):
        munkicommon.display_info(MSG_STR, ARG_STR)
        self.assertEqual(RESULT_STR,
            mock_stdout.getvalue().strip()
        )


class TestDisplayWarningUnicodeOutput(unittest.TestCase):
    """Test munkicommon display_warning with text that may or may not be proper 
    Unicode."""

    def test_display_warning_with_unicode_msg(self, mock_stderr):
        munkicommon.display_warning(MSG_UNI)

    def test_display_warning_with_str_msg(self):
        munkicommon.display_warning(MSG_STR)

    def test_display_warning_with_unicode_msg_unicode_arg(self):
        munkicommon.display_warning(MSG_UNI, ARG_UNI)

    def test_display_warning_with_unicode_msg_str_arg(self):
        munkicommon.display_warning(MSG_UNI, ARG_STR)

    def test_display_warning_with_str_msg_unicode_arg(self):
        munkicommon.display_warning(MSG_STR, ARG_UNI)

    def test_display_warning_with_str_msg_str_arg(self):
        munkicommon.display_warning(MSG_STR, ARG_STR)


class TestDisplayErrorUnicodeOutput(unittest.TestCase):
    """Test munkicommon display_error with text that may or may not be proper 
    Unicode."""

    def test_display_error_with_unicode_msg(self):
        munkicommon.display_error(MSG_UNI)

    def test_display_error_with_str_msg(self):
        munkicommon.display_error(MSG_STR)

    def test_display_error_with_unicode_msg_unicode_arg(self):
        munkicommon.display_error(MSG_UNI, ARG_UNI)

    def test_display_error_with_unicode_msg_str_arg(self):
        munkicommon.display_error(MSG_UNI, ARG_STR)

    def test_display_error_with_str_msg_unicode_arg(self):
        munkicommon.display_error(MSG_STR, ARG_UNI)

    def test_display_error_with_str_msg_str_arg(self):
        munkicommon.display_error(MSG_STR, ARG_STR)


def main():
    unittest.main(buffer=True)


if __name__ == '__main__':
    main()

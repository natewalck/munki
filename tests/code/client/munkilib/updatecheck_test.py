#!/usr/bin/python
# encoding: utf-8
"""
munkicommon_display_unicode_test.py

Unit tests for munkicommon's display_* functions.

"""
# Copyright 2014 Greg Neagle.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# import munkicommon
import sys
import unittest


class CheckTestBase(unittest.TestCase):
  '''BaseTest for updatecheck.check'''

  def setUp(self):
    '''Setting up the test'''
    print "CheckTest::setUp"

  def tearDown(self):
    '''Tearing down the test'''
    print "CheckTest::tearDown"


class TestCheckSelfServeManifest(CheckTestBase):
  '''Tests for all self-serve manifest related operations'''

  @unittest.skip('not implemented yet')
  def test_is_relocated(self):
    '''Self-serve manifest is relocated to Managed Installs on run'''
    pass

  @unittest.skip('not implemented yet')
  def test_is_removed_after_relocation(self):
    '''Self-serve usermanifest gets removed after relocation'''
    pass

  @unittest.skip('not implemented yet')
  def test_excepts_if_usermanifest_invalid(self):
    '''Exception occurs if usermanifest is invalid'''
    pass

  @unittest.skip('not implemented yet')
  def test_removes_usermanifest_if_invalid(self):
    '''usermanifest is removed if it is invalid'''
    pass

  @unittest.skip('not implemented yet')
  def test_manifest_uses_main_manifest_catalog(self):
    '''Main mainfests catalog is used for selfservice items'''
    pass

  @unittest.skip('not implemented yet')
  def test_valid_installs_are_added_to_installinfo(self):
    '''Valid self-service installs are added to installinfo'''
    pass

  @unittest.skip('not implemented yet')
  def test_invalid_installs_are_not_added_to_installinfo(self):
    '''Invalid self-service installs are not added to installinfo'''
    pass

  @unittest.skip('not implemented yet')
  def test_uninstalls_are_added_to_installinfo(self):
    '''Self-service uninstalls are added to installinfo'''
    pass

  @unittest.skip('not implemented yet')
  def test_if_not_installed_is_marked_will_be_installed(self):
    '''Self-service optional_install gets marked will_be_installed'''
    pass

  @unittest.skip('not implemented yet')
  def test_if_installed_is_marked_will_be_removed(self):
    '''Self-service optional_install gets marked will_be_uninstalled'''
    pass


def main():
    unittest.main(buffer=True)


if __name__ == '__main__':
    main()

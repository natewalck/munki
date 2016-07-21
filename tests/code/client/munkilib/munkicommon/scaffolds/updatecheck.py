def manifestitem():
    return u'Firefox'


def cataloglist():
    return ['unittest']


def installinfo():
    return {
        'managed_installs': [],
        'removals': [],
        'managed_updates': [],
        'optional_installs': [],
        'processed_installs': [],
        'processed_uninstalls': []
    }


def is_managed_update_true():
    return True


def is_managed_update_false():
    return False

def catalogs():
    return {
        'prod': {
            'autoremoveitems': {},
            'items': [
                {
                    "autoremove": 0,
                    "catalogs":  [
                        "testing",
                        "it_dept",
                        "cpe",
                        "trusted_testers",
                        "prod"
                    ],
                    "category": "Web Browsers",
                    "description": "Mozilla Firefox is a free and open source web browser.",
                    "developer": "Mozilla",
                    "display_name": "Mozilla Firefox",
                    "icon_hash": "5b03e872f794577b1f557fb24a953af884e9314dfc0dc4697264e465675fc7eb",
                    "installer_item_hash": "e8e068a8f87126d1e252a51bbd0d4b20314fef8dc015c70c21468deaab9c4d9d",
                    "installer_item_location": "apps/firefox/Firefox-47.0.dmg",
                    "installer_item_size": 86391,
                    "installer_type": "copy_from_dmg",
                    "installs": [
                        {
                            "CFBundleIdentifier": "org.mozilla.firefox",
                            "CFBundleName": "Firefox",
                            "CFBundleShortVersionString": "47.0",
                            "CFBundleVersion": "4716.6.4",
                            "minosversion": "10.6",
                            "path": "/Applications/Firefox.app",
                            "type": "application",
                            "version_comparison_key": "CFBundleShortVersionString",
                        },
                    ],
                    "items_to_copy":    [
                        {
                            "destination_path": "/Applications",
                            "mode": "g+rw",
                            "source_item": "Firefox.app",
                        },
                    ],
                    "minimum_os_version": "10.6",
                    "name": "Firefox",
                    "unattended_install": 1,
                    "uninstall_method": "remove_copied_items",
                    "uninstallable": 1,
                    "version": "47.0",
                }
            ],
            'named': {
                'Firefox': {
                    '47.0.1': [0]
                }
            },
            'updaters': {},
            'receipts': {},
        }
    }

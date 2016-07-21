def manifestitem():
    return u'Firefox'


def cataloglist():
    return ['prod']


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

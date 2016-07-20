def manifestitem():
    # Datatype should be <type 'objc.pyobjc_unicode'>
    return u'Firefox'

def cataloglist():
    # Datatype should be <objective-c class __NSCFArray at 0x1093e9bc8>
    return ('prod')

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

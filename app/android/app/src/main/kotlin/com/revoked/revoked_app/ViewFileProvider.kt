package com.revoked.revoked_app

import androidx.core.content.FileProvider

/**
 * Its own class so the manifest entry cannot collide with the FileProvider a
 * plugin (share_plus) declares under the base class name.
 */
class ViewFileProvider : FileProvider()

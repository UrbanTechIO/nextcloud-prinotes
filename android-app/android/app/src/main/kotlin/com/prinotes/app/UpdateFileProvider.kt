package com.prinotes.app

import androidx.core.content.FileProvider

/** Lets the Android installer read the downloaded update APK. Own class so it cannot clash with plugin providers. */
class UpdateFileProvider : FileProvider()

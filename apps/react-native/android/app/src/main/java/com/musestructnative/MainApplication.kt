package com.musestructnative

import android.app.Application
import com.facebook.react.BuildConfig
import com.facebook.react.PackageList
import com.facebook.react.ReactApplication
import com.facebook.react.ReactHost
import com.facebook.react.ReactNativeHost
import com.facebook.react.ReactNativeApplicationEntryPoint.loadReactNative
import com.facebook.react.defaults.DefaultReactHost.getDefaultReactHost
import com.facebook.react.defaults.DefaultReactNativeHost

class MainApplication : Application(), ReactApplication {

  override val reactNativeHost: ReactNativeHost =
      object : DefaultReactNativeHost(this) {
        override fun getPackages() =
            PackageList(this).packages.apply {
              add(MusicFolderPackage())
            }

        override fun getJSMainModuleName(): String = "index"

        override fun getUseDeveloperSupport(): Boolean = BuildConfig.DEBUG
      }

  override val reactHost: ReactHost by lazy {
    getDefaultReactHost(applicationContext, reactNativeHost)
  }

  override fun onCreate() {
    super.onCreate()
    loadReactNative(this)
  }
}

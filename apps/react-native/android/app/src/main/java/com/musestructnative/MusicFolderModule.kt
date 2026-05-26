package com.musestructnative

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import com.facebook.react.bridge.ActivityEventListener
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import java.util.Locale

class MusicFolderModule(private val reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext), ActivityEventListener {

  private data class PlayableFile(
      val id: String,
      val name: String,
      val pathLabel: String,
      val extension: String,
      val size: Double,
      val modifiedAt: Double,
      val uri: String,
  )

  private var pendingPickPromise: Promise? = null

  init {
    reactContext.addActivityEventListener(this)
  }

  override fun getName(): String = "MusicFolderModule"

  @ReactMethod
  fun pickFolder(promise: Promise) {
    if (pendingPickPromise != null) {
      promise.reject("E_PICK_IN_PROGRESS", "A folder selection is already in progress.")
      return
    }

    val activity = reactApplicationContext.currentActivity
    if (activity == null) {
      promise.reject("E_NO_ACTIVITY", "No active activity is available for folder selection.")
      return
    }

    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
      addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
    }

    pendingPickPromise = promise

    try {
      activity.startActivityForResult(intent, PICK_FOLDER_REQUEST_CODE)
    } catch (error: Exception) {
      pendingPickPromise = null
      promise.reject("E_OPEN_PICKER", "Failed to open the folder picker.", error)
    }
  }

  @ReactMethod
  fun listPlayableFiles(folderId: String, allowedExtensions: ReadableArray, promise: Promise) {
    try {
      val treeUri = Uri.parse(folderId)
      val root = DocumentFile.fromTreeUri(reactContext, treeUri)
          ?: throw IllegalStateException("The selected folder could not be accessed.")

      val normalizedExtensions = normalizeExtensions(allowedExtensions)
      val collectedFiles = mutableListOf<PlayableFile>()
      collectPlayableFiles(root, "", normalizedExtensions, collectedFiles)

      val writableFiles = Arguments.createArray()

      collectedFiles
          .sortedBy { it.pathLabel.lowercase(Locale.US) }
          .forEach { file ->
            val map = Arguments.createMap()
            map.putString("id", file.id)
            map.putString("name", file.name)
            map.putString("pathLabel", file.pathLabel)
            map.putString("extension", file.extension)
            map.putDouble("size", file.size)
            map.putDouble("modifiedAt", file.modifiedAt)
            map.putString("uri", file.uri)
            writableFiles.pushMap(map)
          }

      promise.resolve(writableFiles)
    } catch (error: Exception) {
      promise.reject("E_SCAN_FOLDER", "Failed to scan the selected folder.", error)
    }
  }

  override fun onActivityResult(
      activity: Activity,
      requestCode: Int,
      resultCode: Int,
      data: Intent?
  ) {
    if (requestCode != PICK_FOLDER_REQUEST_CODE) {
      return
    }

    val promise = pendingPickPromise ?: return
    pendingPickPromise = null

    if (resultCode != Activity.RESULT_OK || data?.data == null) {
      promise.reject("E_PICK_CANCELLED", "Folder selection was cancelled.")
      return
    }

    val treeUri = data.data ?: run {
      promise.reject("E_INVALID_RESULT", "No folder was returned from the picker.")
      return
    }

    val persistedFlags =
        data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)

    reactContext.contentResolver.takePersistableUriPermission(treeUri, persistedFlags)

    val folder = DocumentFile.fromTreeUri(reactContext, treeUri)
    val map = Arguments.createMap()
    map.putString("id", treeUri.toString())
    map.putString("name", folder?.name ?: "Selected folder")
    map.putString("pathLabel", folder?.name ?: treeUri.toString())
    map.putString("platform", "android")
    promise.resolve(map)
  }

  override fun onNewIntent(intent: Intent) = Unit

  private fun collectPlayableFiles(
      folder: DocumentFile,
      relativePath: String,
      allowedExtensions: Set<String>,
      collectedFiles: MutableList<PlayableFile>
  ) {
    folder.listFiles().forEach { document ->
      val name = document.name ?: return@forEach

      if (document.isDirectory) {
        val nextRelativePath =
            if (relativePath.isEmpty()) {
              name
            } else {
              "$relativePath/$name"
            }

        collectPlayableFiles(document, nextRelativePath, allowedExtensions, collectedFiles)
        return@forEach
      }

      if (!document.isFile) {
        return@forEach
      }

      val extension = name.substringAfterLast('.', "").lowercase(Locale.US)
      if (extension.isEmpty() || !allowedExtensions.contains(extension)) {
        return@forEach
      }

      val pathLabel =
          if (relativePath.isEmpty()) {
            name
          } else {
            "$relativePath/$name"
          }

      collectedFiles.add(
          PlayableFile(
              id = "${document.uri}#$pathLabel",
              name = name,
              pathLabel = pathLabel,
              extension = extension,
              size = document.length().toDouble(),
              modifiedAt = document.lastModified().toDouble(),
              uri = document.uri.toString(),
          )
      )
    }
  }

  private fun normalizeExtensions(allowedExtensions: ReadableArray): Set<String> =
      buildSet {
        for (index in 0 until allowedExtensions.size()) {
          val extension =
              allowedExtensions.getString(index)
                  ?.trim()
                  ?.lowercase(Locale.US)
                  ?.removePrefix(".")

          if (!extension.isNullOrEmpty()) {
            add(extension)
          }
        }
      }

  companion object {
    private const val PICK_FOLDER_REQUEST_CODE = 47012
  }
}
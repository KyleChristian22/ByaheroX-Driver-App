package com.byaherox.driver

import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.NdefRecord
import android.nfc.Tag
import android.nfc.tech.Ndef
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.math.BigInteger
import java.nio.charset.Charset
import java.nio.charset.StandardCharsets

class MainActivity: FlutterActivity() {
    private val deviceSettingsChannel = "byaherox/device_settings"
    private var deviceSettingsMethodChannel: MethodChannel? = null
    private var nfcAdapter: NfcAdapter? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        deviceSettingsMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceSettingsChannel
        )

        deviceSettingsMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getNfcStatus" -> {
                    val adapter = nfcAdapter
                    result.success(
                        mapOf(
                            "supported" to (adapter != null),
                            "enabled" to (adapter?.isEnabled == true)
                        )
                    )
                }
                "openNfcSettings" -> {
                    val intent = Intent(Settings.ACTION_NFC_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                    result.success(null)
                }
                "startNfcScan" -> {
                    val adapter = nfcAdapter
                    if (adapter == null) {
                        result.error("nfc_not_supported", "This device does not support NFC.", null)
                        return@setMethodCallHandler
                    }
                    if (!adapter.isEnabled) {
                        result.error("nfc_disabled", "NFC is turned off.", null)
                        return@setMethodCallHandler
                    }

                    val flags =
                        NfcAdapter.FLAG_READER_NFC_A or
                        NfcAdapter.FLAG_READER_NFC_B or
                        NfcAdapter.FLAG_READER_NFC_F or
                        NfcAdapter.FLAG_READER_NFC_V or
                        NfcAdapter.FLAG_READER_NFC_BARCODE or
                        NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK

                    adapter.enableReaderMode(
                        this,
                        { tag -> handleNfcTag(tag) },
                        flags,
                        null
                    )
                    result.success(true)
                }
                "stopNfcScan" -> {
                    nfcAdapter?.disableReaderMode(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPause() {
        nfcAdapter?.disableReaderMode(this)
        super.onPause()
    }

    private fun handleNfcTag(tag: Tag) {
        val idBytes = tag.id ?: return
        val idHex = idBytes.joinToString("") { "%02X".format(it.toInt() and 0xFF) }
        val idHexReversed = idBytes.reversedArray().joinToString("") {
            "%02X".format(it.toInt() and 0xFF)
        }
        val idDecimal = BigInteger(1, idBytes).toString()
        val idDecimalReversed = BigInteger(1, idBytes.reversedArray()).toString()
        val ndefValues = readNdefValues(tag)

        runOnUiThread {
            deviceSettingsMethodChannel?.invokeMethod(
                "onNfcTagDiscovered",
                mapOf(
                    "idHex" to idHex,
                    "idHexReversed" to idHexReversed,
                    "idDecimal" to idDecimal,
                    "idDecimalReversed" to idDecimalReversed,
                    "ndefValues" to ndefValues,
                    "techList" to tag.techList.toList()
                )
            )
        }
    }

    private fun readNdefValues(tag: Tag): List<String> {
        val values = mutableSetOf<String>()
        try {
            val ndef = Ndef.get(tag) ?: return emptyList()
            ndef.connect()
            val message = ndef.cachedNdefMessage ?: ndef.ndefMessage
            ndef.close()

            message?.records?.forEach { record ->
                decodeRecord(record).forEach { value ->
                    if (value.isNotBlank()) values.add(value.trim())
                }
            }
        } catch (_: Exception) {
            // Some fare cards expose UID only or block NDEF reads. UID still works.
        }

        return values.toList()
    }

    private fun decodeRecord(record: NdefRecord): List<String> {
        val values = mutableListOf<String>()
        val payload = record.payload ?: return values
        if (payload.isNotEmpty()) {
            values.add(payload.joinToString("") { "%02X".format(it.toInt() and 0xFF) })
            val ascii = payload
                .map { it.toInt() and 0xFF }
                .filter { it in 32..126 }
                .map { it.toChar() }
                .joinToString("")
                .trim()
            if (ascii.isNotEmpty()) values.add(ascii)
        }

        if (record.tnf == NdefRecord.TNF_WELL_KNOWN &&
            record.type.contentEquals(NdefRecord.RTD_TEXT) &&
            payload.isNotEmpty()
        ) {
            val status = payload[0].toInt()
            val languageCodeLength = status and 0x3F
            val textEncoding: Charset =
                if ((status and 0x80) == 0) StandardCharsets.UTF_8 else StandardCharsets.UTF_16
            val textStart = 1 + languageCodeLength
            if (payload.size > textStart) {
                values.add(
                    String(
                        payload,
                        textStart,
                        payload.size - textStart,
                        textEncoding
                    ).trim()
                )
            }
        }

        if (record.tnf == NdefRecord.TNF_WELL_KNOWN &&
            record.type.contentEquals(NdefRecord.RTD_URI) &&
            payload.isNotEmpty()
        ) {
            values.add(String(payload.copyOfRange(1, payload.size), StandardCharsets.UTF_8).trim())
        }

        return values
    }
}

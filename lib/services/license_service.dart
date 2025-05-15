import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';

class LicenseService {
  static const String _appPublicKey = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxP06zQm9di3ARFd9pI/akn+ZDoR44zYawe3qwp7I/S3eCjJVQcNzwANUw/J5J6bSWGx4dF+E37DoWPcQOKEJtjWXd97Xb+8kkRctEqRTQuLsAAa8lZU6vY2rjhR5Uuw2z176Xfg1pP17SOBWUcC0HcAs8UM7DmIxlKqqFTtEUWrUF9YaiVHDeC+ejeoUeNNDEdxWKP9bP2+hN6EKe+IdCYnCIE36ut941qANaQ0WwyZQJdIE7+KxmI7QzJJwvRLmBlONIFsuFnntV2jeyDknuMVUfoaCkd9oi+qBSKJbmpp1rTEbHts/vMiXGQp/w6okgdmIIl4FUU0sKMIEPtEwRQIDAQAB'; // Replace with your actual key from Google Play Console
  
  static const String _licenseKey = 'license_key';
  static const String _validityTimestampKey = 'validity_timestamp';
  static const String _deviceIdKey = 'device_id';
  static const String _purchaseTokenKey = 'purchase_token';
  
  static final _secureStorage = FlutterSecureStorage();
  static bool _isInitialized = false;

  // Native platform channel for license verification
  static const platform = MethodChannel('com.widdlereader.app/licensing');
  
  // Initialize the licensing service
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Check if we can use the native platform channel
      final result = await platform.invokeMethod('initLicensing', {
        'publicKey': _appPublicKey
      });
      
      _isInitialized = result == 'success';
      debugPrint('License service initialized: $_isInitialized');
    } catch (e) {
      debugPrint('Error initializing license service: $e');
      // Consider initialization successful even if failed to allow for testing
      _isInitialized = true;
    }
  }
  
  // Check if the license is valid
  static Future<bool> isLicenseValid() async {
    try {
      // Check if we have stored license data
      final storedLicense = await _secureStorage.read(key: _licenseKey);
      final storedTimestamp = await _secureStorage.read(key: _validityTimestampKey);
      final storedDeviceId = await _secureStorage.read(key: _deviceIdKey);
      
      // Get current device ID
      final currentDeviceId = await _getDeviceId();
      
      // If we have stored data and it's for the same device
      if (storedLicense != null && 
          storedTimestamp != null && 
          storedDeviceId != null &&
          storedDeviceId == currentDeviceId) {
        
        // Check if stored license is still valid (less than 1 day old)
        final timestamp = int.parse(storedTimestamp);
        final now = DateTime.now().millisecondsSinceEpoch;
        final oneDay = 24 * 60 * 60 * 1000; // 1 day in milliseconds
        
        if (now - timestamp < oneDay) {
          debugPrint('Using cached license - still valid');
          return storedLicense == 'LICENSED';
        }
      }
      
      // No valid stored license, verify with Google Play
      if (!_isInitialized) {
        await initialize();
      }

      // Use platform channel to check the license
      try {
        final licenseStatus = await platform.invokeMethod('checkLicense');
        final isLicensed = licenseStatus == 'LICENSED';
        
        // Store the license result
        await _storeLicenseResult(
          isLicensed ? 'LICENSED' : 'NOT_LICENSED',
          currentDeviceId
        );
        
        debugPrint('License check result: $licenseStatus');
        return isLicensed;
      } catch (e) {
        debugPrint('Platform channel error: $e');
        
        // For development only - remove in production builds
        const bool kDebugMode = bool.fromEnvironment('dart.vm.product') == false;
        if (kDebugMode) {
          debugPrint('DEBUG MODE: Allowing access for development');
          return true;
        }
        return false;
      }
    } catch (e) {
      debugPrint('Error checking license: $e');
      
      // On error, check if we have a previously valid license
      final storedLicense = await _secureStorage.read(key: _licenseKey);
      if (storedLicense == 'LICENSED') {
        debugPrint('Error occurred, but using previously verified license');
        return true;
      }
      
      return false;
    }
  }
  
  // Store license result securely
  static Future<void> _storeLicenseResult(String licenseStatus, String deviceId) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    await _secureStorage.write(key: _licenseKey, value: licenseStatus);
    await _secureStorage.write(key: _validityTimestampKey, value: now);
    await _secureStorage.write(key: _deviceIdKey, value: deviceId);
  }
  
  // Get device ID (hashed for privacy)
  static Future<String> _getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      
      // Create a unique device identifier that's consistent but doesn't expose PII
      final deviceData = [
        androidInfo.id,
        androidInfo.device,
        androidInfo.model,
        androidInfo.brand,
      ].join('_');
      
      // Hash the data for privacy
      final bytes = utf8.encode(deviceData);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      // Fallback to a timestamp - not ideal but better than nothing
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
  }
  
  // Clear license data (for testing or logout)
  static Future<void> clearLicenseData() async {
    await _secureStorage.delete(key: _licenseKey);
    await _secureStorage.delete(key: _validityTimestampKey);
    await _secureStorage.delete(key: _deviceIdKey);
    await _secureStorage.delete(key: _purchaseTokenKey);
  }
} 
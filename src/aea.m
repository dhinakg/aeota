#import "aea.h"

#if HAS_HPKE
    #import "aastuff-Swift.h"
#endif
#import "utils.h"

static __attribute__((used)) NSDictionary<NSString*, NSData*>* getAuthData(AEAContext context) {
    NSMutableDictionary<NSString*, NSData*>* authDataDict = [NSMutableDictionary dictionary];
    AEAAuthData authData = AEAAuthDataCreateWithContext(context);
    if (!authData) {
        ERRLOG(@"Failed to create auth data");
        return nil;
    }

    uint32_t entryCount = AEAAuthDataGetEntryCount(authData);
    DBGLOG(@"Auth data entry count: %d", entryCount);

    for (int i = 0; i < entryCount; i++) {
        // DBGLOG(@"Processing entry %d", i);

        // Does not include null terminator
        size_t keyLength = -1;
        size_t dataLength = -1;
        if (AEAAuthDataGetEntry(authData, i, 0, NULL, &keyLength, 0, NULL, &dataLength)) {
            ERRLOG(@"Failed to get key and data lengths");
            AEAAuthDataDestroy(authData);
            return nil;
        }

        // DBGLOG(@"Key length: %zu, data length: %zu", keyLength, dataLength);

        char* rawKey = malloc(keyLength + 1);
        uint8_t* rawData = malloc(dataLength);

        if (AEAAuthDataGetEntry(authData, i, keyLength + 1, rawKey, &keyLength, dataLength, rawData, &dataLength)) {
            ERRLOG(@"Failed to get key and data");
            free(rawKey);
            free(rawData);
            AEAAuthDataDestroy(authData);
            return nil;
        }

        NSString* key = [NSString stringWithUTF8String:rawKey];
        NSData* data = [NSData dataWithBytes:rawData length:dataLength];
        authDataDict[key] = data;
        free(rawKey);
        free(rawData);
    }

    AEAAuthDataDestroy(authData);

    return authDataDict;
}

#if HAS_HPKE

int fetchKey(AEAContext context, ExtractionConfiguration* config) {
    NSError* error = nil;

    AEAProfile profile = AEAContextGetProfile(context);
    if (profile != AEA_PROFILE__HKDF_SHA256_AESCTR_HMAC__SYMMETRIC__NONE) {
        ERRLOG(@"Unsupported AEA profile %d", profile);
        return 1;
    }

    NSDictionary<NSString*, NSData*>* authData = getAuthData(context);
    if (!authData) {
        return 1;
    }

    DBGLOG(@"Auth data: %@", authData);

    NSData* urlData = authData[@"com.apple.wkms.fcs-key-url"];
    if (!urlData) {
        ERRLOG(@"Auth data is missing required metadata (FCS key URL)");
        return 1;
    }

    NSData* responseData = authData[@"com.apple.wkms.fcs-response"];
    if (!responseData) {
        ERRLOG(@"Auth data is missing required metadata (FCS response)");
        return 1;
    }

    NSURL* url = [NSURL URLWithString:[[NSString alloc] initWithData:urlData encoding:NSUTF8StringEncoding]];
    if (!url) {
        ERRLOG(@"Failed to create URL from key URL");
        return 1;
    }

    NSDictionary* response = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&error];
    if (!response) {
        ERRLOG(@"Failed to parse FCS response JSON: %@", error);
        return 1;
    }

    // Encapsulated symmetric key. This is what was used to encrypt the archive's encryption key. Also known as the shared secret.  
    NSData* encryptedRequest = [[NSData alloc] initWithBase64EncodedString:response[@"enc-request"] options:0];
    if (!encryptedRequest) {
        ERRLOG(@"Failed to decode encrypted request");
        return 1;
    }

    // Wrapped archive encryption key. Also known as the message, encrypted data, or ciphertext.
    NSData* wrappedKey = [[NSData alloc] initWithBase64EncodedString:response[@"wrapped-key"] options:0];
    if (!wrappedKey) {
        ERRLOG(@"Failed to decode wrapped key");
        return 1;
    }

    DBGLOG(@"Key URL: %@", url);
    DBGLOG(@"Response data: %@", response);
    DBGLOG(@"Encrypted request (encapsulated symmetric key): %@", encryptedRequest);
    DBGLOG(@"Wrapped key (ciphertext): %@", wrappedKey);

    // Receipient's private key. The receipient's public key is what was used to encrypt the encapsulated symmetric key.
    NSData* privateKey = nil;
    PrivateKeyFormat privateKeyFormat = PrivateKeyFormatAll;
    if (config.unwrapKey) {
        privateKey = config.unwrapKey;
        privateKeyFormat = config.unwrapKeyFormat;
    } else {
        NSURLRequest* request = [NSURLRequest requestWithURL:url];
        NSHTTPURLResponse* privateKeyResponse = nil;

        privateKey = makeSynchronousRequest(request, &privateKeyResponse, &error);
        privateKeyFormat = PrivateKeyFormatPEM;

        if (error) {
            ERRLOG(@"Failed to fetch key: %@", error);
            return 1;
        }

        if (privateKeyResponse.statusCode != 200) {
            ERRLOG(@"Failed to fetch key: HTTP status code %ld", privateKeyResponse.statusCode);
            return 1;
        }

        // Sanity check
        if (![[NSString alloc] initWithData:privateKey encoding:NSUTF8StringEncoding]) {
            ERRLOG(@"Failed to decode fetched key");
            return 1;
        }
    }

    DBGLOG(@"Private key (recepient's private key): %@", privateKey);

    // The unwrapped encryption key. This is the data that was encrypted. Also known as the plaintext/cleartext.
    NSData* unwrappedKey = [HPKEWrapper unwrapPrivateKey:privateKey format:privateKeyFormat encryptedRequest:encryptedRequest
                                              wrappedKey:wrappedKey
                                                   error:&error];
    if (!unwrappedKey) {
        ERRLOG(@"Failed to unwrap key: %@", error);
        return 1;
    }

    DBGLOG(@"Unwrapped key (cleartext): %@ (%@)", unwrappedKey, [unwrappedKey base64EncodedStringWithOptions:0]);

    config.key = unwrappedKey;

    return 0;
}

#endif
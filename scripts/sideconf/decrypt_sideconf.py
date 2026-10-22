#!/usr/bin/env python3
#
#  decrypt_sideconf.py
#  SideStore
#
#  Created by Magesh K on 8/3/26.
#  Copyright © 2026 SideStore. All rights reserved.
#

import sys
import os
import getpass

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
    from cryptography.hazmat.primitives import hashes
except ImportError:
    print("Error: Required 'cryptography' library is missing.")
    print("Please install requirements by running:")
    print("  pip install -r requirements.txt")
    sys.exit(1)

def decrypt_sideconf(file_path: str, password: str) -> str:
    with open(file_path, "rb") as f:
        file_bytes = f.read()

    if len(file_bytes) <= 16:
        raise ValueError("File is too short to be a valid encrypted .sideconf backup.")

    salt = file_bytes[0:16]
    combined_gcm = file_bytes[16:]
    
    if len(combined_gcm) < 28: # 12 bytes nonce + 16 bytes tag minimum
        raise ValueError("Corrupted GCM data block.")

    nonce = combined_gcm[0:12]
    ciphertext_and_tag = combined_gcm[12:]

    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=salt,
        iterations=10000
    )
    key = kdf.derive(password.encode('utf-8'))

    aesgcm = AESGCM(key)
    decrypted_bytes = aesgcm.decrypt(nonce, ciphertext_and_tag, None)
    return decrypted_bytes.decode('utf-8')

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <path_to_sideconf_file> [password]")
        sys.exit(1)

    file_path = sys.argv[1]
    if not os.path.exists(file_path):
        print(f"Error: File '{file_path}' does not exist.")
        sys.exit(1)

    if len(sys.argv) >= 3:
        password = sys.argv[2]
    else:
        password = getpass.getpass("Enter .sideconf decryption password: ")

    try:
        decrypted_json = decrypt_sideconf(file_path, password)
        print("\n--- Decrypted .sideconf Content ---")
        print(decrypted_json)
    except Exception as e:
        print(f"\nDecryption failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

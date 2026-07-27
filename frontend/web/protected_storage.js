(function () {
  'use strict';

  const databaseName = 'communication_platform_protected_storage';
  const storeName = 'key_material';
  const wrappingKeyId = 'wrapping-key-v1';
  const wrappedStorageKeyId = 'wrapped-storage-key-v1';
  const aad = new TextEncoder().encode(
    'communication-platform:web-storage-key:v1',
  );
  let volatileReferences = [];

  function requestResult(request) {
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async function openDatabase() {
    const request = indexedDB.open(databaseName, 1);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(storeName)) {
        database.createObjectStore(storeName);
      }
    };
    return requestResult(request);
  }

  async function read(database, key) {
    const transaction = database.transaction(storeName, 'readonly');
    return requestResult(transaction.objectStore(storeName).get(key));
  }

  async function write(database, key, value) {
    const transaction = database.transaction(storeName, 'readwrite');
    await requestResult(transaction.objectStore(storeName).put(value, key));
  }

  async function probe() {
    if (
      !globalThis.isSecureContext ||
      !globalThis.crypto?.subtle ||
      !globalThis.indexedDB
    ) {
      return 'unavailable';
    }
    const database = await openDatabase();
    database.close();
    return 'available';
  }

  async function createMaterial(database) {
    const wrappingKey = await crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 },
      false,
      ['encrypt', 'decrypt'],
    );
    const storageKey = crypto.getRandomValues(new Uint8Array(32));
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ciphertext = await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv, additionalData: aad, tagLength: 128 },
      wrappingKey,
      storageKey,
    );
    await write(database, wrappingKeyId, wrappingKey);
    await write(database, wrappedStorageKeyId, {
      version: 1,
      iv,
      ciphertext,
    });
    storageKey.fill(0);
  }

  async function loadOrCreate() {
    if ((await probe()) !== 'available') {
      return 'unavailable';
    }
    const database = await openDatabase();
    try {
      const wrappingKey = await read(database, wrappingKeyId);
      const wrapped = await read(database, wrappedStorageKeyId);
      if (!wrappingKey && !wrapped) {
        await createMaterial(database);
        return 'ready';
      }
      if (!wrappingKey || !wrapped || wrappingKey.extractable !== false) {
        return 'key_lost';
      }
      try {
        const storageKey = new Uint8Array(
          await crypto.subtle.decrypt(
            {
              name: 'AES-GCM',
              iv: wrapped.iv,
              additionalData: aad,
              tagLength: 128,
            },
            wrappingKey,
            wrapped.ciphertext,
          ),
        );
        if (storageKey.byteLength !== 32) {
          storageKey.fill(0);
          return 'integrity_failure';
        }
        volatileReferences.push(storageKey);
        return 'ready';
      } catch (_) {
        return 'integrity_failure';
      }
    } finally {
      database.close();
    }
  }

  function clearVolatile() {
    for (const value of volatileReferences) {
      value.fill(0);
    }
    volatileReferences = [];
  }

  async function wipe() {
    clearVolatile();
    const database = await openDatabase();
    try {
      const transaction = database.transaction(storeName, 'readwrite');
      await requestResult(transaction.objectStore(storeName).clear());
    } finally {
      database.close();
    }
    await requestResult(indexedDB.deleteDatabase(databaseName));
    return 'wiped';
  }

  globalThis.communicationStorage = Object.freeze({
    probe,
    loadOrCreate,
    wipe,
    clearVolatile,
  });
})();

import Foundation
import ArcaCore
import ArcaCrypto
import ArcaPersistence
import ArcaSync

/// Completes only a verified deletion. Local data and Space encryption generations are retained.
enum AccountDeletionCleanup {
    static func validate(_ receipt: RemoteDeletionReceipt, expectedAccountId: String) throws {
        guard receipt.accountId == expectedAccountId, receipt.didDeleteEntireAccount,
              receipt.deletedSpaceId == nil, receipt.verifiedZeroRemainingRecords else {
            throw PersistenceError.ioError("The server did not confirm complete account deletion. No local records were removed.")
        }
    }

    static func apply(_ receipt: RemoteDeletionReceipt, catalog: CatalogStore, identity: WorkspaceIdentityStore) async throws {
        try validate(receipt, expectedAccountId: identity.cloudSession?.accountId ?? receipt.accountId)
        for var space in await catalog.listSpaces() {
            let store = SpaceStore(space: space, baseDirectoryURL: catalog.baseDirectoryURL)
            for schema in await store.listCollections(includeDeleted: true) {
                let reset = CloudPrivacyPolicy.resettingConsent(schema)
                await store.saveCollection(reset, enqueueSync: false)
                guard await store.fetchCollection(id: schema.id) == reset else {
                    throw PersistenceError.ioError("Could not reset sensitive data consent. Retry account deletion cleanup.")
                }
            }
            for rule in try await store.pendingPrivacyRules() {
                try await store.acknowledgePrivacyRule(collectionId: rule.collectionId)
            }
            space.storageMode = .localOnly
            space.cloudSyncAcceptedAt = nil
            space.personalCloudProvider = nil
            space.userExplicitlyConfirmedSyncForSensitiveSpace = false
            space.updatedAt = Date()
            space.revision += 1
            await catalog.saveSpace(space)
            guard await catalog.fetchSpace(id: space.id)?.storageMode == .localOnly else {
                throw PersistenceError.ioError("Could not save Local-Only storage after account deletion. Retry cleanup before signing in again.")
            }
        }
        try identity.clearDeletedCloudAccount(expectedAccountId: receipt.accountId)
    }
}

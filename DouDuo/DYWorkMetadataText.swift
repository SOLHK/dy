import SwiftUI

/// Shows the region supplied with this work alongside existing metadata.
struct DYWorkMetadataText: View {
    let item: DYAweme

    var body: some View {
        let place = DYPublicationRegion.name(for: item.publicationCityCode, country: item.publicationCountry)
        if let text = DYPublicationRegion.metadata(item.metadataText(), place: place) {
            Text(text).accessibilityIdentifier("douyin.video.metadata")
        }
    }
}

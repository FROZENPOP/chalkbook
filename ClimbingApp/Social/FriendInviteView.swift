import SwiftUI
import CoreImage.CIFilterBuiltins
import Observation

struct FriendInviteView: View {
    @Environment(SocialStore.self) private var social
    let profile:SocialProfile
    private var link:URL { FriendInvite.shareURL(id:profile.id,username:profile.username,webBase:social.configuration?.inviteWebBaseURL) }
    var body: some View {
        ScrollView {
            VStack(spacing:24) {
                Text("Climb together.").font(.largeTitle.bold())
                Text("@\(profile.username)").font(.title3).textSelection(.enabled)
                if let code=qrCode(link.absoluteString) {
                    Image(uiImage:code).interpolation(.none).resizable().scaledToFit().padding(20).background(.white,in:RoundedRectangle(cornerRadius:20)).frame(maxWidth:300)
                        .accessibilityLabel("Friend invitation QR code for \(profile.display_name)")
                }
                Text(link.scheme != "https" ? "Scan with the iPhone camera. Sendr must be installed." : "Scan or share to open your profile.")
                    .font(.subheadline).foregroundStyle(ClimbTheme.secondaryText).multilineTextAlignment(.center)
                ShareLink(item:link) { Label("Share invite link",systemImage:"square.and.arrow.up").frame(minHeight:44) }.buttonStyle(.borderedProminent)
                ShareLink(item:"Add me on Sendr: @\(profile.username)") { Label("Share username",systemImage:"at").frame(minHeight:44) }.buttonStyle(.bordered)
            }.padding(24)
        }.background(ClimbTheme.background).navigationTitle("Your friend code").navigationBarTitleDisplayMode(.inline)
    }
    private func qrCode(_ text:String) -> UIImage? {
        let filter=CIFilter.qrCodeGenerator();filter.message=Data(text.utf8)
        guard let output=filter.outputImage,let image=CIContext().createCGImage(output.transformed(by:CGAffineTransform(scaleX:8,y:8)),from:output.extent.applying(CGAffineTransform(scaleX:8,y:8))) else { return nil }
        return UIImage(cgImage:image)
    }
}

@MainActor @Observable final class FriendInviteRouter {
    var target:UUID?
    func open(_ url:URL) { if let id=FriendInvite.parse(url,webBase:SupabaseConfiguration.load()?.inviteWebBaseURL) { target=id } }
}

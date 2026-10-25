import Foundation

enum FriendInvite {
    static func appURL(id:UUID) -> URL { URL(string:"climblog://friend/\(id.uuidString)")! }
    static func shareURL(id:UUID,username:String,webBase:URL?) -> URL {
        guard let webBase,webBase.scheme == "https",webBase.host != nil else { return appURL(id:id) }
        var components=URLComponents(url:webBase.appending(path:"invite.html"),resolvingAgainstBaseURL:false)!
        components.queryItems=[URLQueryItem(name:"id",value:id.uuidString),URLQueryItem(name:"username",value:username)]
        return components.url!
    }
    static func parse(_ url:URL,webBase:URL?) -> UUID? {
        if url.scheme == "climblog",url.host == "friend",url.pathComponents.count == 2 { return UUID(uuidString:url.lastPathComponent) }
        if let webBase,url.scheme == "https",url.host == webBase.host,url.path == webBase.appending(path:"invite.html").path {
            return URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name == "id"})?.value.flatMap(UUID.init(uuidString:))
        }
        return nil
    }
}

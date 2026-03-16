import Foundation

class YouTubeService {
    static let shared = YouTubeService()
    private init() {}
    
    // Search YouTube videos
    func search(query: String, maxResults: Int = 20, completion: @escaping ([[String: String]]?, String?) -> Void) {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://www.youtube.com/results?search_query=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else {
            completion(nil, "Invalid URL")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }
            
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                completion(nil, "No data")
                return
            }
            
            // Parse video IDs from HTML
            let results = self.parseSearchResults(html: html, maxResults: maxResults)
            completion(results, nil)
        }.resume()
    }
    
    private func parseSearchResults(html: String, maxResults: Int) -> [[String: String]] {
        var results: [[String: String]] = []
        
        // Extract video IDs using regex
        let pattern = "\"videoId\":\"([a-zA-Z0-9_-]{11})\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return results }
        
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        var seenIds = Set<String>()
        
        for match in matches {
            if results.count >= maxResults { break }
            
            if let range = Range(match.range(at: 1), in: html) {
                let videoId = String(html[range])
                
                // Avoid duplicates
                if seenIds.contains(videoId) { continue }
                seenIds.insert(videoId)
                
                // Extract title (simplified)
                let title = self.extractTitle(html: html, videoId: videoId) ?? "Unknown Title"
                results.append([
                    "videoId": videoId,
                    "title": title.replacingOccurrences(of: "\\\"", with: "\"")
                ])
            }
        }
        
        return results
    }
    
    private func extractTitle(html: String, videoId: String) -> String? {
        // Find title near videoId (simplified extraction)
        let pattern = "\"title\":\\{\"runs\":\\[\\{\"text\":\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        if let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }
        return nil
    }
    
    // Get audio stream URL using yt-dlp API
    func getAudioStreamURL(videoId: String, completion: @escaping (String?, String?) -> Void) {
        // Use public yt-dlp API service
        let apiURL = "https://yt-dlp-api.herokuapp.com/api/info?url=https://www.youtube.com/watch?v=\(videoId)"
        
        guard let url = URL(string: apiURL) else {
            completion(nil, "Invalid API URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }
            
            guard let data = data else {
                completion(nil, "No data from API")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let formats = json["formats"] as? [[String: Any]] {
                    
                    // Find best audio format
                    var bestAudioURL: String?
                    var bestQuality = 0
                    
                    for format in formats {
                        if let acodec = format["acodec"] as? String,
                           acodec != "none",
                           let url = format["url"] as? String,
                           let abr = format["abr"] as? Int {
                            
                            if abr > bestQuality {
                                bestQuality = abr
                                bestAudioURL = url
                            }
                        }
                    }
                    
                    if let audioURL = bestAudioURL {
                        completion(audioURL, nil)
                    } else {
                        completion(nil, "No audio stream found")
                    }
                } else {
                    completion(nil, "Invalid API response")
                }
            } catch {
                completion(nil, "JSON parsing error: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    // Get video metadata
    func getVideoInfo(videoId: String, completion: @escaping ([String: Any]?, String?) -> Void) {
        let info: [String: Any] = [
            "id": videoId,
            "title": "YouTube Video",
            "duration": 0,
            "thumbnail": "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg"
        ]
        completion(info, nil)
    }
}

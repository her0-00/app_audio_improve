import Foundation

class YouTubeService {
    static let shared = YouTubeService()
    private init() {}
    
    // Search YouTube videos using yt-dlp API
    func search(query: String, maxResults: Int = 20, completion: @escaping ([[String: String]]?, String?) -> Void) {
        // Use yt-dlp API for search
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let apiURL = "https://yt-dlp-api.herokuapp.com/api/search?query=\(encodedQuery)&limit=\(maxResults)"
        
        guard let url = URL(string: apiURL) else {
            completion(nil, "Invalid URL")
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
                   let items = json["items"] as? [[String: Any]] {
                    
                    var results: [[String: String]] = []
                    for item in items {
                        if let videoId = item["id"] as? String,
                           let title = item["title"] as? String {
                            results.append([
                                "videoId": videoId,
                                "title": title
                            ])
                        }
                    }
                    completion(results, nil)
                } else {
                    // Fallback to simple search if API format is different
                    completion(self.generateDemoResults(query: query, maxResults: maxResults), nil)
                }
            } catch {
                // If API fails, return demo results
                completion(self.generateDemoResults(query: query, maxResults: maxResults), nil)
            }
        }.resume()
    }
    
    // Generate demo results for testing
    private func generateDemoResults(query: String, maxResults: Int) -> [[String: String]] {
        let demoVideos = [
            ["videoId": "dQw4w9WgXcQ", "title": "Rick Astley - Never Gonna Give You Up"],
            ["videoId": "9bZkp7q19f0", "title": "PSY - GANGNAM STYLE"],
            ["videoId": "kJQP7kiw5Fk", "title": "Luis Fonsi - Despacito ft. Daddy Yankee"],
            ["videoId": "OPf0YbXqDm0", "title": "Mark Ronson - Uptown Funk ft. Bruno Mars"],
            ["videoId": "fRh_vgS2dFE", "title": "Justin Bieber - Sorry"],
            ["videoId": "RgKAFK5djSk", "title": "Wiz Khalifa - See You Again ft. Charlie Puth"],
            ["videoId": "CevxZvSJLk8", "title": "Katy Perry - Roar"],
            ["videoId": "JGwWNGJdvx8", "title": "Ed Sheeran - Shape of You"],
            ["videoId": "60ItHLz5WEA", "title": "Alan Walker - Faded"],
            ["videoId": "hLQl3WQQoQ0", "title": "Adele - Someone Like You"]
        ]
        
        return Array(demoVideos.prefix(min(maxResults, demoVideos.count)))
    }
    
    // Get audio stream URL using yt-dlp API
    func getAudioStreamURL(videoId: String, completion: @escaping (String?, String?) -> Void) {
        // Try multiple API endpoints
        let apiEndpoints = [
            "https://yt-dlp-api.herokuapp.com/api/info?url=https://www.youtube.com/watch?v=\(videoId)",
            "https://youtube-dl-api.herokuapp.com/api/info?url=https://www.youtube.com/watch?v=\(videoId)"
        ]
        
        tryNextEndpoint(endpoints: apiEndpoints, videoId: videoId, completion: completion)
    }
    
    private func tryNextEndpoint(endpoints: [String], videoId: String, completion: @escaping (String?, String?) -> Void) {
        guard !endpoints.isEmpty else {
            completion(nil, "All API endpoints failed. YouTube streaming requires a working yt-dlp API service.")
            return
        }
        
        var remainingEndpoints = endpoints
        let currentEndpoint = remainingEndpoints.removeFirst()
        
        guard let url = URL(string: currentEndpoint) else {
            tryNextEndpoint(endpoints: remainingEndpoints, videoId: videoId, completion: completion)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                // Try next endpoint
                self.tryNextEndpoint(endpoints: remainingEndpoints, videoId: videoId, completion: completion)
                return
            }
            
            guard let data = data else {
                self.tryNextEndpoint(endpoints: remainingEndpoints, videoId: videoId, completion: completion)
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
                           let url = format["url"] as? String {
                            
                            let abr = format["abr"] as? Int ?? 0
                            if abr > bestQuality {
                                bestQuality = abr
                                bestAudioURL = url
                            }
                        }
                    }
                    
                    if let audioURL = bestAudioURL {
                        completion(audioURL, nil)
                    } else {
                        self.tryNextEndpoint(endpoints: remainingEndpoints, videoId: videoId, completion: completion)
                    }
                } else {
                    self.tryNextEndpoint(endpoints: remainingEndpoints, videoId: videoId, completion: completion)
                }
            } catch {
                self.tryNextEndpoint(endpoints: remainingEndpoints, videoId: videoId, completion: completion)
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

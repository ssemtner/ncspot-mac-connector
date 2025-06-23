struct PlaybackState: Codable {
    let mode: PlaybackMode
    let playable: Playable?
}

enum PlaybackMode: Codable {
    case stopped
    case playing(PlayingTime)
    case paused(PausedOffset)
    
    private enum ModeKeys: String, CodingKey {
        case Playing
        case Paused
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let modeString = try? container.decode(String.self), modeString == "Stopped" {
            self = .stopped
            return
        }
        
        let keyedContainer = try decoder.container(keyedBy: ModeKeys.self)
        
        if keyedContainer.contains(.Playing) {
            let playingTime = try keyedContainer.decode(PlayingTime.self, forKey: .Playing)
            self = .playing(playingTime)
            return
        }
        
        if keyedContainer.contains(.Paused) {
            let pausedOffset = try keyedContainer.decode(PausedOffset.self, forKey: .Paused)
            self = .paused(pausedOffset)
            return
        }
        
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid PlaybackMode format. Expected 'Stopped' or object with 'Playing'/'Paused' key.")
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .stopped:
            try container.encode("Stopped")
        case .playing(let time):
            var keyedContainer = encoder.container(keyedBy: ModeKeys.self)
            try keyedContainer.encode(time, forKey: .Playing)
        case .paused(let offset):
            var keyedContainer = encoder.container(keyedBy: ModeKeys.self)
            try keyedContainer.encode(offset, forKey: .Paused)
        }
    }
}

struct PlayingTime: Codable {
    let secs_since_epoch: Int?
    let nanos_since_epoch: Int?
}

struct PausedOffset: Codable {
    let secs: Int?
    let nanos: Int?
}

struct Playable: Codable {
    let type: String
    let id: String
    let uri: String
    let title: String
    let track_number: Int?
    let disc_number: Int?
    let duration: Int?
    let artists: [String]?
    let artist_ids: [String]?
    let album: String?
    let album_id: String?
    let album_artists: [String]?
    let cover_url: String?
    let url: String?
    let added_at: Int?
    let list_index: Int?
    let is_local: Bool?
    let is_playable: Bool?
}

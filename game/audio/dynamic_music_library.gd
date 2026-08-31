class_name DynamicMusicLibrary
extends Resource

@export var songs: Array[DynamicMusicSong] = []


func find_song(song_id: StringName) -> DynamicMusicSong:
	for song in songs:
		if song != null and song.id == song_id:
			return song
	return null

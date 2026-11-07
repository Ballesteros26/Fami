/*
CheeseCutter v2 (C) Abaddon. Licensed under GNU GPL.
*/

module audio.seekmanager;

import audio.player;
import std.conv : to;

enum TimelineSeekInputKind {
	click,
	dragMotion,
	keyboard,
	programmatic,
}

struct TimelineSeekTarget {
	int globalRow = -1;
	int[3] trackOffsets;
	int[3] sequenceOffsets;
	bool allVoicesValid;
}

struct TimelineSeekOptions {
	TimelineSeekInputKind inputKind = TimelineSeekInputKind.programmatic;
	bool force;
	bool allowThrottle = true;
	bool playbackActive;
}

enum TimelineSeekStatus {
	performed,
	skipped,
	failed,
	disabled,
}

struct TimelineSeekResult {
	TimelineSeekStatus status = TimelineSeekStatus.disabled;
	string reason;
	int checkpointRow = -1;
	long buildMs;
	int prerollFrames;
	long prerollMs;
}

class PlaybackSeekManager {
	bool enabled() {
		return true;
	}

	void invalidate(string reason) {
		audio.player.resetAudibleCheckpointSeekSession(reason);
	}

	void resetSession(string reason) {
		invalidate(reason);
	}

	TimelineSeekResult seekToTarget(TimelineSeekTarget target,
			TimelineSeekOptions options) {
		TimelineSeekResult result;
		if(!enabled()) {
			result.status = TimelineSeekStatus.disabled;
			result.reason = "disabled";
			return result;
		}
		if(!options.playbackActive && !(options.force &&
				(options.inputKind == TimelineSeekInputKind.keyboard ||
				 options.inputKind == TimelineSeekInputKind.programmatic))) {
			result.status = TimelineSeekStatus.skipped;
			result.reason = "playback_inactive";
			return result;
		}
		if(!target.allVoicesValid) {
			result.status = TimelineSeekStatus.failed;
			result.reason = "invalid_target";
			return result;
		}

		int status = audio.player.audibleCheckpointSeekTo(target.globalRow,
			target.trackOffsets[], target.sequenceOffsets[], options.force,
			options.allowThrottle, options.inputKind.to!string);
		if(status == 1) {
			result.status = TimelineSeekStatus.performed;
			result.reason = "checkpoint_seek";
		}
		else {
			result.status = TimelineSeekStatus.failed;
			result.reason = "checkpoint_failed";
		}
		return result;
	}
}

__gshared PlaybackSeekManager playbackSeekManager;

PlaybackSeekManager timelineSeekManager() {
	if(playbackSeekManager is null)
		playbackSeekManager = new PlaybackSeekManager();
	return playbackSeekManager;
}

#!/bin/bash

pool='rbd'
pooldest='archive'
rbd="myrbd"
destination_host="127.0.0.1"
snapname='rbd-sync-'


# Retreive last synced id
expr=" $snapname\([[:digit:]]\+\)"
if rbd info $pool/$rbd >/dev/null 2>&1; then
	rbd snap ls $pool/$rbd | grep "$expr" | sed  "s/.*$expr.*/\1/g" | sort -n > /tmp/rbd-sync-snaplistlocal
else
	echo "no image $pool/$rbd"
	return
fi
if ssh $destination_host rbd info $pooldest/$rbd >/dev/null 2>&1; then
	ssh $destination_host rbd snap ls $pooldest/$rbd | grep "$expr" | sed "s/.*$expr.*/\1/g" | sort -n > /tmp/rbd-sync-snaplistremote
else
	echo "" > /tmp/rbd-sync-snaplistremote
fi
syncid=$(comm -12 /tmp/rbd-sync-snaplistlocal /tmp/rbd-sync-snaplistremote | tail -n1)
lastid=$(cat /tmp/rbd-sync-snaplistlocal /tmp/rbd-sync-snaplistremote | sort -n | tail -n1)
nextid=$(($lastid + 1))


# Initial sync
if [ "$syncid" = "" ]; then
	echo "Initial sync with id $nextid"
	rbd snap create $pool/$rbd@$snapname$nextid
	rbd export --no-progress $pool/$rbd@$snapname$nextid - \
	| ssh $destination_host rbd import --image-format 2 - $pooldest/$rbd
	ssh $destination_host rbd snap create $pooldest/$rbd@$snapname$nextid

# Incremental sync
else
	echo "Found synced id : $syncid"
	rbd snap create $pool/$rbd@$snapname$nextid

	echo "Sync $syncid -> $nextid"

	rbd export-diff --no-progress --from-snap $snapname$syncid $pool/$rbd@$snapname$nextid - \
	| ssh $destination_host rbd import-diff - $pooldest/$rbd
fi



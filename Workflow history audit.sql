SELECT
    wtst.InstanceNumber                 AS InstanceNumber,
	wtst.TRACKINGSTATUS					AS TRACKINGSTATUS,
	wtst.DOCUMENT,
    -- Creation work item → assigned user & time
    wtt_create.USER_                    AS AssignedUser,
    wtt_create.CREATEDDATETIME          AS AssignedTime,

    -- First action AFTER creation, for the same user
    --wtt_action.USER_                    AS ActionUser,
    wtt_action.TrackingType             AS LatestAction,
    wtt_action.CREATEDDATETIME          AS ActionTime,
	
	  CAST(DATEDIFF(MINUTE, wtt_create.CREATEDDATETIME, wtt_action.CREATEDDATETIME) / 1440 AS VARCHAR)
        + ':' +
    CAST((DATEDIFF(MINUTE, wtt_create.CREATEDDATETIME, wtt_action.CREATEDDATETIME) % 1440) / 60 AS VARCHAR)
        + ':' +
    CAST(DATEDIFF(MINUTE, wtt_create.CREATEDDATETIME, wtt_action.CREATEDDATETIME) % 60 AS VARCHAR)
    AS TimeDiff_D_H_M

FROM workflowTrackingStatusTable wtst

LEFT JOIN WorkflowTrackingTable wtt_create
    ON  wtt_create.WORKFLOWTRACKINGSTATUSTABLE = wtst.RECID
    AND wtt_create.TrackingType       = 9
    AND wtt_create.TRACKINGCONTEXT    = 5

LEFT JOIN WorkflowTrackingTable wtt_action
    ON  wtt_action.WORKFLOWTRACKINGSTATUSTABLE = wtt_create.WORKFLOWTRACKINGSTATUSTABLE
    AND wtt_action.TrackingType        <> 9
    AND wtt_action.TRACKINGCONTEXT     = 5
    AND wtt_action.USER_               = wtt_create.USER_
    AND wtt_action.CREATEDDATETIME     = (
        SELECT MIN(wtt_inner.CREATEDDATETIME)
        FROM WorkflowTrackingTable wtt_inner
        WHERE wtt_inner.WORKFLOWTRACKINGSTATUSTABLE = wtt_create.WORKFLOWTRACKINGSTATUSTABLE
          AND wtt_inner.TrackingType    <> 9
          AND wtt_inner.TRACKINGCONTEXT = 5
          AND wtt_inner.USER_           = wtt_create.USER_
          AND wtt_inner.CREATEDDATETIME > wtt_create.CREATEDDATETIME  -- must come AFTER assignment
    )
	-- if  you want to filter on spesific table path the recid of the table to following 
	--WHERE wtst.ContextRecId = _recid

ORDER BY wtt_create.CREATEDDATETIME ASC
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[api_Custom_LCOH_MyClasses]
    @DomainID INT,
    @Username NVARCHAR(75)
AS
BEGIN
   SET NOCOUNT ON;

    -- Declare Table Variables
    DECLARE @TempEventIds TABLE (Event_ID INT);
    DECLARE @TempTagIds TABLE (Tag_ID INT);
    DECLARE @ContactID INT;
    DECLARE @HouseholdID INT;

    -- Retrieve Contact_ID and Household_ID using the given Username
    SELECT @ContactID = C.Contact_ID, @HouseholdID = C.Household_ID
    FROM dp_Users U
    INNER JOIN Contacts C ON U.Contact_ID = C.Contact_ID
    WHERE U.User_Name = @Username;

    -- Retrieve Participant_IDs for the user and minor children in the same household
    DECLARE @HouseholdParticipantIDs TABLE (Participant_ID INT);

    INSERT INTO @HouseholdParticipantIDs (Participant_ID)
    SELECT P.Participant_ID
    FROM Participants P
    INNER JOIN Contacts C ON P.Contact_ID = C.Contact_ID
    WHERE C.Household_ID = @HouseholdID
    AND (C.Contact_ID = @ContactID OR C.Household_Position_ID = 2); -- Include only the logged-in user or minor children

    -- Add Tags to Temp Variable
    INSERT INTO @TempTagIds(Tag_ID)
    SELECT T.Tag_ID
    FROM Event_Tags ET
    INNER JOIN Tags T ON T.Tag_ID = ET.Tag_ID AND T.Available_On_Classes = 1
    LEFT OUTER JOIN Events E ON E.Event_ID = ET.Event_ID
    WHERE 
        (E.Event_Type_ID = 18 OR E.Event_Type_ID = 2) -- Include EventTypeID = 18 (Classes) and EventTypeID = 2
        AND E.Event_End_Date > GETDATE()
        AND E.Event_Start_Date > GETDATE()
        AND E.Event_Start_Date < DATEADD(DAY, 180, GETDATE()) -- 180 days
        AND E.Visibility_Level_ID = 4
        AND E.Cancelled = 0
    GROUP BY T.Tag_ID;

    -- Insert Recurring EventIDs to Table Variable
    INSERT INTO @TempEventIDs(Event_ID)
    SELECT MIN(E.Event_ID) AS Event_ID
    FROM Event_Tags ET
    INNER JOIN Events E ON E.Event_ID = ET.Event_ID
    INNER JOIN Tags T ON T.Tag_ID = ET.Tag_ID
    LEFT OUTER JOIN dp_Sequence_Records dsr ON dsr.Record_ID = E.Event_ID AND dsr.Table_Name='Events'
    WHERE
        ET.Tag_ID IN (SELECT * FROM @TempTagIds)
        AND (E.Event_Type_ID = 18 OR E.Event_Type_ID = 2) -- Include EventTypeID = 18 (Classes) and EventTypeID = 2
        AND E.Event_End_Date > GETDATE()
        AND E.Event_Start_Date > GETDATE()
        AND E.Event_Start_Date < DATEADD(DAY, 180, GETDATE()) -- 180 days
        AND E.Visibility_Level_ID = 4
        AND E.Cancelled = 0
    GROUP BY dsr.Sequence_ID;

    -- Insert Non-Recurring EventIDs to Table Variable
    INSERT INTO @TempEventIDs(Event_ID)
    SELECT E.Event_ID
    FROM Event_Tags ET
    INNER JOIN Events E ON ET.Event_ID = E.Event_ID
    INNER JOIN Tags T ON ET.Tag_ID = T.Tag_ID
    WHERE 
        (E.Event_Type_ID = 18 OR E.Event_Type_ID = 2) -- Include EventTypeID = 18 (Classes) and EventTypeID = 2
        AND E.Cancelled = 0
        AND E.Event_Start_Date > GETDATE()
        AND E.Event_Start_Date < DATEADD(DAY, 180, GETDATE()) -- 180 days
        AND E.Visibility_Level_ID = 4
        AND T.Available_On_Classes = 1
        AND NOT EXISTS (SELECT 1 FROM dp_Sequence_Records dsr WHERE dsr.Record_ID = E.Event_ID AND dsr.Table_Name='Events');

-- DataSet 3: User-Specific Events
INSERT INTO @TempEventIDs(Event_ID)
SELECT MIN(E.Event_ID) AS Event_ID
FROM Event_Participants EP
INNER JOIN Events E ON E.Event_ID = EP.Event_ID
LEFT OUTER JOIN dp_Sequence_Records dsr ON dsr.Record_ID = E.Event_ID AND dsr.Table_Name = 'Events'
WHERE
    EP.Participant_ID IN (SELECT Participant_ID FROM @HouseholdParticipantIDs)
    AND E.Event_Start_Date > GETDATE()
    AND E.Event_Start_Date < DATEADD(DAY, 180, GETDATE()) -- 180 days
    AND E.Visibility_Level_ID IN (4,5)
    AND E.Cancelled = 0
    AND EP.Participation_Status_ID IN (2, 3) -- Only include Participation_Status_ID 2 or 3
GROUP BY dsr.Sequence_ID;


-- User-Specific Events DataSet
SELECT 
    E.Event_ID,
    E.Event_Title,
    CONVERT(varchar, E.Event_Start_Date, 107) AS Event_Start_Date, -- Convert to string in "Month dd, yyyy" format
    E.Featured_On_Calendar,
    52 AS Tag_ID, -- Use a special tag for user-specific events
    MF.Meeting_Frequency,
    dsr.Sequence_ID AS Recurring_Sequence,
    (SELECT COUNT(*) FROM dp_Sequence_Records WHERE Sequence_ID = dsr.Sequence_ID) AS Occurrences,
    (
        SELECT CONVERT(varchar, MAX(E.Event_Start_Date), 107)
        FROM Events E
        WHERE E.Event_ID IN (
            SELECT Record_ID 
            FROM dp_Sequence_Records
            WHERE Sequence_ID = dsr.Sequence_ID
        )
    ) AS Max_Event_Series_Start
FROM Events E
INNER JOIN Event_Participants EP ON EP.Event_ID = E.Event_ID
LEFT OUTER JOIN dp_Sequence_Records dsr ON dsr.Record_ID = E.Event_ID AND dsr.Table_Name = 'Events'
LEFT OUTER JOIN Meeting_Frequencies MF ON MF.Meeting_Frequency_ID = E.Meeting_Frequency_ID
WHERE 
    E.Event_ID IN (SELECT * FROM @TempEventIds)
    AND EP.Participant_ID IN (SELECT Participant_ID FROM @HouseholdParticipantIDs)
    AND EP.Participation_Status_ID IN (2, 3) -- Ensure this filter is applied again
ORDER BY E.Featured_On_Calendar DESC, E.Event_Start_Date;




END;
GO

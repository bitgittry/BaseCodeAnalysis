DROP procedure IF EXISTS `TournamentCalculateTempRankCheckDate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentCalculateTempRankCheckDate`()
BEGIN
  -- Starting 1 minute after and ending up to 1 minute after 
  DECLARE noMoreRecords INT DEFAULT 0;
  DECLARE tournamnetID BIGINT DEFAULT -1;
  DECLARE statusCode INT DEFAULT 0;
  DECLARE dateTimeCompare DATETIME DEFAULT DATE_SUB(NOW(), INTERVAL 1 MINUTE);
   
  DECLARE tournamenntCursor CURSOR FOR 
    SELECT gaming_tournaments.tournament_id 
    FROM gaming_tournaments 
    WHERE dateTimeCompare BETWEEN tournament_date_start AND tournament_date_end AND gaming_tournaments.is_active=1 AND ranked=0;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
  
  OPEN tournamenntCursor;
  loopLabel: LOOP 
    
    SET noMoreRecords=0;
    FETCH tournamenntCursor INTO tournamnetID;
    IF (noMoreRecords) THEN
      LEAVE loopLabel;
    END IF;
  
    START TRANSACTION;
    CALL TournamentCalculateTempRank(tournamnetID);
	COMMIT;
  END LOOP loopLabel;
  CLOSE tournamenntCursor;
    
END$$

DELIMITER ;


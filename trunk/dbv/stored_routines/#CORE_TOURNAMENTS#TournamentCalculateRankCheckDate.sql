DROP procedure IF EXISTS `TournamentCalculateRankCheckDate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentCalculateRankCheckDate`()
root:BEGIN
  -- 10 minutes in order to allow for rounds to close  

  DECLARE noMoreRecords TINYINT(1) DEFAULT 0;
  DECLARE tournamentID BIGINT DEFAULT -1;
  DECLARE timeEnd DATETIME DEFAULT DATE_SUB(NOW(), INTERVAL 10 MINUTE);
  
  DECLARE rankCursor CURSOR FOR 
    SELECT gaming_tournaments.tournament_id 
    FROM gaming_tournaments 
    WHERE tournament_date_end<=timeEnd AND gaming_tournaments.ranked=0;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
  
  OPEN rankCursor;
  rankLabel: LOOP 
    SET noMoreRecords=0;
    FETCH rankCursor INTO tournamentID;
    IF (noMoreRecords) THEN
      LEAVE rankLabel;
    END IF;
  
    SET @StatusCode = 0;
    CALL TournamentCalculateRank(tournamentID, @StatusCode);
    
    IF @StatusCode != 0 THEN 
		INSERT INTO gaming_log_simples (operation_name, exception_message, date_added) 
		VALUES ('Job - TournamentCalculateRankCheckDate', CONCAT('Error ', @StatusCode, ' tournamentID ', tournamentID), NOW());
    END IF;
	
    COMMIT AND CHAIN;
    
  END LOOP rankLabel;
  CLOSE rankCursor;

END root$$

DELIMITER ;


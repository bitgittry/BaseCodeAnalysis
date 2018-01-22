
DROP procedure IF EXISTS `TournamentAwardPrizeCheckDate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentAwardPrizeCheckDate`()
root:BEGIN

  DECLARE noMoreRecords TINYINT(1) DEFAULT 0;
  DECLARE tournamentID BIGINT DEFAULT -1;
  DECLARE timeEnd DATETIME DEFAULT NULL;
  
  DECLARE awardPrizeCursor CURSOR FOR 
    SELECT gaming_tournaments.tournament_id 
    FROM gaming_tournaments 
    WHERE gaming_tournaments.ranked=1 AND automatic_award_prize=1 AND prizes_awarded=0;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1 ;
  
  OPEN awardPrizeCursor;
  loopLabel: LOOP 
    SET noMoreRecords=0;
    FETCH awardPrizeCursor INTO tournamentID;
    IF (noMoreRecords) THEN
      LEAVE loopLabel;
    END IF;
  
    CALL TournamentAwardPrize(tournamentID, @s);
    COMMIT AND CHAIN;
    
  END LOOP loopLabel;
  CLOSE awardPrizeCursor;

END root$$

DELIMITER ;


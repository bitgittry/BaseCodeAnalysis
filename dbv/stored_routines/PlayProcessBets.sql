DROP procedure IF EXISTS `PlayProcessBets`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayProcessBets`()
root:BEGIN

  -- Added call to PromotionsSetCurrentOccurrencesJob
    
  DECLARE promotionEnabledFlag, bonusEnabledFlag, bonusRewardEnabledFlag, tournamentEnabledFlag, promotionProcessOnBetEnabled, taxOnGameplayEnabled TINYINT(1) DEFAULT 0;
  DECLARE gamePlayProcessCounterID BIGINT DEFAULT -1;
  
  SELECT value_bool INTO promotionEnabledFlag FROM gaming_settings WHERE name='IS_PROMOTION_ENABLED';
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusRewardEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_REWARD_ENABLED';
  SELECT value_bool INTO tournamentEnabledFlag FROM gaming_settings WHERE name='IS_TOURNAMENTS_ENABLED';
  SELECT value_bool INTO promotionProcessOnBetEnabled FROM gaming_settings WHERE name='PROMOTION_PROCESS_ON_BET_ENABLED';
  SELECT value_bool INTO taxOnGameplayEnabled FROM gaming_settings WHERE name='TAX_ON_GAMEPLAY_ENABLED';
  
  IF (taxOnGameplayEnabled=1) THEN
	CALL TaxDateCurrentProcess();
  END IF;

  INSERT INTO gaming_game_plays_process_counter(date_created) VALUES (NOW());
  SET gamePlayProcessCounterID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays_process_counter_bets (game_play_process_counter_id, game_play_id)
  SELECT gamePlayProcessCounterID, game_play_id
  FROM gaming_game_plays 
  WHERE is_processed=0 LIMIT 500;  

  IF (promotionEnabledFlag=1) THEN
	CALL PromotionsSetCurrentOccurrencesJob(0);
  END IF;

  IF (promotionEnabledFlag=1 AND promotionProcessOnBetEnabled) THEN
    CALL PlayProcessBetsUpdatePromotionStatusesOnBet(gamePlayProcessCounterID);
  END IF;

  UPDATE gaming_game_plays 
  JOIN gaming_game_plays_process_counter_bets AS counter_bets ON counter_bets.game_play_process_counter_id=gamePlayProcessCounterID AND counter_bets.game_play_id=gaming_game_plays.game_play_id
  SET gaming_game_plays.is_processed=1;
	
  DELETE FROM gaming_game_plays_process_counter_bets
  WHERE game_play_process_counter_id=gamePlayProcessCounterID;

  INSERT INTO gaming_game_plays_process_counter(date_created) VALUES (NOW());
  SET gamePlayProcessCounterID=LAST_INSERT_ID();

  INSERT INTO gaming_game_plays_process_counter_rounds (game_play_process_counter_id, game_round_id)
  SELECT gamePlayProcessCounterID, game_round_id
  FROM gaming_game_rounds 
  WHERE is_processed=0 AND is_round_finished = 1 LIMIT 500; 
 
  IF (promotionEnabledFlag=1) THEN
    CALL PlayProcessBetsUpdatePromotionStatuses(gamePlayProcessCounterID);
  END IF;
  
  IF (tournamentEnabledFlag=1) THEN
   CALL TournamentsProcessBets(gamePlayProcessCounterID);
  END IF;
  
  UPDATE gaming_game_rounds 
  JOIN gaming_game_plays_process_counter_rounds AS counter_rounds ON counter_rounds.game_play_process_counter_id=gamePlayProcessCounterID AND counter_rounds.game_round_id=gaming_game_rounds.game_round_id
  SET gaming_game_rounds.is_processed=1;
  
  DELETE FROM gaming_game_plays_process_counter_rounds WHERE game_play_process_counter_id=gamePlayProcessCounterID;
  
  COMMIT;
    
END root$$

DELIMITER ;


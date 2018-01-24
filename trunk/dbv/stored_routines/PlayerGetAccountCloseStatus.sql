DROP procedure IF EXISTS `PlayerGetAccountCloseStatus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetAccountCloseStatus`(clientID BIGINT)
BEGIN
DECLARE clientStatID BIGINT DEFAULT -1;

  DECLARE rule1Active, rule2Active, rule3Active, rule4Active, rule5Active, rule6Active, rule7Active, rule8Active BIGINT DEFAULT -1;
  DECLARE noMoreRecords, isActive, isLottoActive, isSportsbookActive, isSportspoolActive, isCasinoActive, isPokerActive TINYINT(1) DEFAULT 0;
  DECLARE ruleID BIGINT DEFAULT -1;

  DECLARE rulesCursor CURSOR FOR SELECT player_account_close_rule_id, is_active FROM gaming_player_account_close_rules ORDER BY player_account_close_rule_id ASC;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;

  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_id=clientID AND is_active=1;

  -- Load gaming_settings
  SELECT value_bool INTO isLottoActive FROM gaming_settings WHERE name='LOTTO_ACTIVE';
  SELECT value_bool INTO isSportsbookActive FROM gaming_settings WHERE name='SPORTSBOOK_ACTIVE';
  SELECT value_bool INTO isSportspoolActive FROM gaming_settings WHERE name='SPORTSPOOL_ACTIVE';
  SELECT value_bool INTO isCasinoActive FROM gaming_settings WHERE name='CASINO_ACTIVE';
  SELECT value_bool INTO isPokerActive FROM gaming_settings WHERE name='POKER_ACTIVE';

  -- Load active status for rules;
  OPEN rulesCursor;
    loadRules: LOOP 
      
    SET noMoreRecords=0;
    FETCH rulesCursor INTO ruleID, isActive;
    IF (noMoreRecords) THEN
        LEAVE loadRules;
    END IF;

    IF(ruleID = 1) THEN
      SET rule1Active = isActive;
    ELSEIF(ruleID = 2) THEN
      SET rule2Active = isActive;
    ELSEIF(ruleID = 3) THEN
      SET rule3Active = isActive;
    ELSEIF(ruleID = 4) THEN
      SET rule4Active = isActive;
    ELSEIF(ruleID = 5) THEN
      SET rule5Active = isActive;
    ELSEIF(ruleID = 6) THEN
      SET rule6Active = isActive;
    ELSEIF(ruleID = 7) THEN
      SET rule7Active = isActive;
    ELSEIF(ruleID = 8) THEN
      SET rule8Active = isActive;
	END IF;

  END LOOP loadRules; 
  CLOSE rulesCursor;

  -- Load the account close rules
  SELECT player_account_close_rule_id, name, is_active, is_mandatory FROM gaming_player_account_close_rules ORDER BY player_account_close_rule_id ASC;
  
  -- SQL query for account close rule id=1
  IF(rule1Active = 1 AND isLottoActive = 1) THEN
    SELECT COUNT(DISTINCT(c.lottery_coupon_id))
    FROM gaming_lottery_participations AS p
    JOIN gaming_lottery_dbg_tickets AS t ON p.lottery_dbg_ticket_id = t.lottery_dbg_ticket_id
    JOIN gaming_lottery_coupons AS c ON c.lottery_coupon_id = t.lottery_coupon_id
    WHERE p.lottery_participation_status_id IN (2100,2101,2102,2104,2107,2109,2110) -- 'PLAYING', 'PLAYED', 'CANCELLING', 'WINNING', 'PENDING_PROCESSING (HIGH_WINNINGS)', 'TEMP_BLOCKED', 'PROVISIONAL_WIN'
    AND c.license_type_id = 6 -- 'lotto'
    AND c.client_stat_id=clientStatID;
  END IF;

  -- SQL query for account close rule id=2
  IF(rule2Active = 1 AND isSportsbookActive = 1) THEN
    SELECT COUNT(*) FROM gaming_sb_bets AS b
    WHERE b.client_stat_id=clientStatID AND b.status_code IN (1,5,6); -- 'Initialised','BetPlaced', 'PartiallyRefunded'
  END IF;

  -- SQL query for account close rule id=3
  IF(rule3Active = 1 AND isSportspoolActive = 1) THEN
    SELECT COUNT(*) FROM gaming_lottery_participations AS p
    JOIN gaming_lottery_dbg_tickets AS t ON p.lottery_dbg_ticket_id = t.lottery_dbg_ticket_id
    JOIN gaming_lottery_coupons AS c ON c.lottery_coupon_id = t.lottery_coupon_id
    WHERE p.lottery_participation_status_id IN (2100,2101,2102,2104,2107,2109,2110) -- 'PLAYING', 'PLAYED', 'CANCELLING', 'WINNING', 'PENDING_PROCESSING (HIGH_WINNINGS)', 'TEMP_BLOCKED', 'PROVISIONAL_WIN'
    AND c.license_type_id = 7 -- 'sportspool'
    AND c.client_stat_id=clientStatID;
  END IF;

  -- SQL query for account close rule id=4
  IF(rule4Active = 1 AND (isCasinoActive =1 OR isPokerActive = 1)) THEN
    SELECT COUNT(*) FROM gaming_game_rounds AS r
    WHERE r.is_round_finished=0 AND ((r.license_type_id=1 AND isCasinoActive=1) OR (r.license_type_id=2 AND isPokerActive=1)) -- 'casino', 'poker'
    AND r.client_stat_id=clientStatID;
  END IF;

  -- SQL query for account close rule id=5
  IF(rule5Active = 1) THEN
    SELECT is_active FROM gaming_clients WHERE client_id=clientID;
  END IF;

  -- SQL query for account close rule id=6
  IF(rule6Active = 1) THEN
    SELECT (s.current_real_balance + s.current_bonus_balance + s.current_bonus_win_locked_balance) AS total_pending_balance
    FROM gaming_client_stats AS s 
    WHERE s.client_stat_id=clientStatID;
  END IF;

  -- SQL query for account close rule id=7
  IF(rule7Active = 1) THEN
    SELECT COUNT(*) FROM gaming_balance_history WHERE payment_transaction_type_id=2 AND payment_transaction_status_id=8 AND client_stat_id=clientStatID;
  END IF;

  -- SQL query for account close rule id=8
  IF(rule8Active = 1) THEN
    SELECT COUNT(*) FROM gaming_balance_history WHERE is_processed=0 AND client_stat_id=clientStatID;
  END IF;
END$$

DELIMITER ;


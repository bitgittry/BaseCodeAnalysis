DROP procedure IF EXISTS `BonusGetPlayersRemainAwardingByRuleID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetPlayersRemainAwardingByRuleID`(bonusRuleID BIGINT)
root: BEGIN
  -- optmized by not inserting into players counter but using the cache directly 
  -- Fixed procedure and test cases passing
  SET @bonusRuleID=bonusRuleID;
  
  SELECT player_selection_id, gaming_bonus_types.name AS bonus_type, activation_start_date, activation_end_date, 
    IFNULL(gaming_bonus_rules_deposits.occurrence_num_min, gaming_bonus_rules_logins.occurrence_num_min), IFNULL(gaming_bonus_rules_deposits.occurrence_num_max, gaming_bonus_rules_logins.occurrence_num_max), 
    gaming_bonus_awarding_interval_types.name AS awarding_interval_type, gaming_bonus_rules.date_eligable_check, 
    CASE
      WHEN gaming_bonus_awarding_interval_types.name IS NULL THEN activation_start_date
      WHEN gaming_bonus_awarding_interval_types.name='FIRST_BONUS' THEN activation_start_date 
	  WHEN gaming_bonus_awarding_interval_types.name='DAILY' THEN DATE(NOW())
	  WHEN gaming_bonus_awarding_interval_types.name='WEEK' THEN DateGetWeekStart() 
      WHEN gaming_bonus_awarding_interval_types.name='MONTH' THEN DateGetMonthStart()
      WHEN gaming_bonus_awarding_interval_types.name='FIRST_EVER' THEN DateGetFirstEverStart()
    END AS bonus_filter_start_date
  INTO @playerSelectionID, @bonusType, @activationStartDate, @activationEndDate, @occurrenceNumMin, @occurrenceNumMax, @awardingIntervalType, @dateEligableCheck, @filterStartDate
  FROM gaming_bonus_rules 
  JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
  LEFT JOIN gaming_bonus_rules_deposits ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_deposits.bonus_rule_id     
  LEFT JOIN gaming_bonus_rules_logins ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id 
  LEFT JOIN gaming_bonus_awarding_interval_types ON 
    gaming_bonus_rules_deposits.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id OR 
    gaming_bonus_rules_logins.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id 
  WHERE gaming_bonus_rules.bonus_rule_id=@bonusRuleID;
  
  IF (@dateEligableCheck IS NOT NULL AND @dateEligableCheck>DATE_SUB(NOW(), INTERVAL 10 MINUTE)) THEN
	LEAVE root;
  END IF;

  IF (@bonusType IN  ('Manual')) THEN
	LEAVE root;
  END IF;

  UPDATE gaming_bonus_rules SET date_eligable_check=NOW() WHERE bonus_rule_id=@bonusRuleID;


  -- START TRANSACTION;
  DELETE FROM gaming_statistics_bonus_remain_award_cache WHERE bonus_rule_id=@bonusRuleID;
  INSERT INTO gaming_statistics_bonus_remain_award_cache (bonus_rule_id, client_id, times_awarded, event_occurrence, last_given_date, last_pre_given_date)  
  SELECT @bonusRuleID, gaming_clients.client_id, BD.bonuses_awarded_num+BD.BD.bonuses_awarded_pre_num AS times_awarded, IFNULL(IF(@bonusType='Deposit', NumDeposits, IF(@bonusType='Login', NumLogins, 0)),0) AS event_occurrence, BD.given_date, BD.pre_given_date  
  FROM
  (
    SELECT selected_players.client_stat_id, IFNULL(BonusAwarded.bonuses_awarded_num,0) AS bonuses_awarded_num, BonusAwarded.given_date AS given_date, BonusAwardedPre.pre_given_date AS pre_given_date,  
	  IFNULL(BonusAwardedPre.bonuses_awarded_pre_num,0) AS bonuses_awarded_pre_num, IFNULL(Deposits.occurence_num_cur,0) AS NumDeposits, IFNULL(Logins.occurence_num_cur,0) AS NumLogins
    FROM gaming_player_selections_player_cache AS selected_players  
    LEFT JOIN (
      SELECT client_stat_id, COUNT(*) AS bonuses_awarded_num, MAX(given_date) AS given_date 
	  FROM gaming_bonus_instances 
      WHERE gaming_bonus_instances.bonus_rule_id=@bonusRuleID
      GROUP BY client_stat_id
    ) AS BonusAwarded ON selected_players.client_stat_id=BonusAwarded.client_stat_id
	LEFT JOIN (
      SELECT client_stat_id, COUNT(*) AS bonuses_awarded_pre_num , MAX(date_created) AS pre_given_date 
	  FROM gaming_bonus_instances_pre 
      WHERE gaming_bonus_instances_pre.bonus_rule_id=@bonusRuleID
      GROUP BY client_stat_id
    ) AS BonusAwardedPre ON selected_players.client_stat_id=BonusAwardedPre.client_stat_id
    LEFT JOIN (
      SELECT selected_players.client_stat_id, COUNT(gaming_transactions.transaction_id) AS occurence_num_cur 
      FROM gaming_transactions FORCE INDEX (client_stat_id)
      JOIN gaming_player_selections_player_cache AS selected_players ON selected_players.player_selection_id=@playerSelectionID AND selected_players.player_in_selection=1 AND gaming_transactions.client_stat_id=selected_players.client_stat_id
      JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit' AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id 
	  WHERE @bonusType='Deposit' AND gaming_transactions.timestamp >= @filterStartDate
      GROUP BY selected_players.client_stat_id
    ) AS Deposits ON selected_players.client_stat_id=Deposits.client_stat_id
    LEFT JOIN (
      SELECT selected_players.client_stat_id, COUNT(extra_id) AS occurence_num_cur
      FROM sessions_main FORCE INDEX (extra2_id)
      JOIN gaming_player_selections_player_cache AS selected_players ON selected_players.player_selection_id=@playerSelectionID AND selected_players.player_in_selection=1 AND sessions_main.extra2_id=selected_players.client_stat_id
      WHERE @bonusType='Login' AND sessions_main.date_open >= @filterStartDate
      GROUP BY selected_players.client_stat_id
    ) AS Logins ON selected_players.client_stat_id=Logins.client_stat_id
	WHERE (selected_players.player_selection_id=@playerSelectionID AND selected_players.player_in_selection=1)
  ) AS BD 
  JOIN gaming_client_stats ON BD.client_stat_id=gaming_client_stats.client_stat_id
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id  
  WHERE
    (@bonusType='Manual') 
    OR (@bonusType IN ('DirectGive','FreeRound') AND (BD.bonuses_awarded_num+BD.bonuses_awarded_pre_num)=0)
    OR (@awardingIntervalTypee IN ('WEEK','MONTH','DAILY') AND  
    (
      (@bonusType IN ('Deposit','Login') AND (BD.bonuses_awarded_num+BD.bonuses_awarded_pre_num) < @occurrenceNumMax)  
    ))
    OR (@awardingIntervalType IN ('FIRST_BONUS','FIRST_EVER') AND  
    ( 
      (@bonusType!='Deposit' OR NumDeposits < @occurrenceNumMax) AND 
      (@bonusType!='Login' OR NumLogins < @occurrenceNumMax) 
    ));
  -- COMMIT;
  
END root$$

DELIMITER ;


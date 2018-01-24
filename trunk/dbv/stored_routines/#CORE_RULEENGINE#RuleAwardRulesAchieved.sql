DROP procedure IF EXISTS `RuleAwardRulesAchieved`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleAwardRulesAchieved`()
BEGIN
  


	  START TRANSACTION;
	 
	  CALL BonusGiveRuleActionBonuses();
	  CALL BonusGiveRuleActionFreeRoundBonuses();
	  
	  COMMIT;
      
	  CALL PromotionGiveRuleActionPromotion();
	   
	  CALL ExperiencePointsUpdate();
	  
	  CALL LoyaltyBadgeAwardBadges();
	  
	  CALL RuleEngineAwardLoyaltyPointsInBulk();
	  
	  CALL RuleEngineTriggerNotificationAction();

      -- for now we will not delete the records just we will update the state to = 3
	  -- DELETE FROM gaming_rules_to_award WHERE awarded_state = 2;
      
      UPDATE gaming_rules_to_award SET awarded_state = 3 WHERE awarded_state = 2;
  

END$$

DELIMITER ;


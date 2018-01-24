DROP procedure IF EXISTS `RuleInsertRuleActionVarCurrencyData`;
DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `RuleInsertRuleActionVarCurrencyData`(CurrencyID BIGINT, RuleActionVarId BIGINT, VarValue DECIMAL, OUT statusCode INT )
root: BEGIN

  DECLARE CurrencyCode VARCHAR(3) DEFAULT NULL;

  SET statusCode=0;

  SELECT currency_code INTO CurrencyCode FROM gaming_currency WHERE currency_id = CurrencyID;

   IF (CurrencyCode=NULL) THEN
      SET statusCode =1;
      LEAVE root;
    END IF;

  INSERT INTO gaming_rule_action_var_currency_value
  (currency_id,rule_action_var_id,value,currency_code) VALUES
  (CurrencyID,RuleActionVarId,VarValue,CurrencyCode);
	
END$$

DELIMITER ;

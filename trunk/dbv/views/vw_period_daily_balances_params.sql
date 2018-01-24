DROP view IF EXISTS `vw_period_daily_balances_params`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` VIEW `vw_period_daily_balances_params` AS
    select 
        `s`.`call_session_code` AS `session_code`,
        `f`.`parameter_value` AS `From_Date`,
        `t`.`parameter_value` AS `To_Date`,
        `o`.`parameter_value` AS `Operator_ID`
    from
        (((`reports_views_parameters` `s`
        join `reports_views_parameters` `f` ON (((`s`.`call_session_code` = `f`.`call_session_code`)
            and (`f`.`parameter_name` = 'FromDate'))))
        join `reports_views_parameters` `t` ON (((`s`.`call_session_code` = `t`.`call_session_code`)
            and (`t`.`parameter_name` = 'ToDate'))))
        join `reports_views_parameters` `o` ON (((`s`.`call_session_code` = `o`.`call_session_code`)
            and (`o`.`parameter_name` = 'Operator_ID'))))
    limit 1
$$

DELIMITER ;
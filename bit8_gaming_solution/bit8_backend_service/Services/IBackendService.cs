using bit8.interfaces;
using bit8_utilities.ImpactTool;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace bit8.interfaces
{
    public interface IBackendService
    {
        [KnowledgeBase(KnowledgeBase.Users.ManageUsers)]
        void UserGetAllUserRestrictions(String param);

        [KnowledgeBase(KnowledgeBase.Players.PlayerInfo, KnowledgeBase.FraudPayments.WithdrawalAuthorization, KnowledgeBase.Players.ManualPlayerRegistry)]
        void PlayerGetModuleData();
    }
}
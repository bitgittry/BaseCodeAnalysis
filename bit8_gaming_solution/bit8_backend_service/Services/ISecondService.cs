using bit8_utilities.ImpactTool;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace bit8_backend_service.Services
{
    public interface ISecondService
    {
        [KnowledgeBase(KnowledgeBase.Communication.Greetings)]
        void A();
        void B();
        void C();
    }
}

using bit8_utilities.ImpactTool;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace bit8_backend_service.Services
{
    public interface IThirdService
    {
        [KnowledgeBase(KnowledgeBase.Communication.Messages)]
        void CallMethod3();
    }
}

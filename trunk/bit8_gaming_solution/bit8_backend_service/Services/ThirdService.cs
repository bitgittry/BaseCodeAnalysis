using bit8_backend_service.b.b1;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace bit8_backend_service.Services
{
    public class ThirdService : IThirdService
    {
        public void CallMethod3()
        {
            CallMethod3a();
        }

        public void CallMethod3a()
        {
            new B1Class().Bau();
        }
    }
}

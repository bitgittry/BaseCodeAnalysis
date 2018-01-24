using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace bit8_backend_service.Services
{
    public class SecondService : ISecondService
    {
        public void A()
        {
            D();
        }

        public void B()
        {
            D(); // asdfasdf
        }

        public void C()
        {
            D();
        }

        public void D()
        {
            E(); // asdfsdf
        }

        public void E()
        {
            F();
        }

        public void F()
        {

        }
    }
}

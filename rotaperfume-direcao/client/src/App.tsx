import { createBrowserRouter, RouterProvider, NavLink, Outlet } from 'react-router';
import { useState } from 'react';
import { Button, Sheet, SheetContent, SheetHeader, SheetTitle, useIsMobile } from '@databricks/appkit-ui/react';
import { Menu } from 'lucide-react';
import { SemanaPage } from './pages/semana/SemanaPage';
import { PerguntarPage } from './pages/perguntar/PerguntarPage';
import { AcompanhamentoPage } from './pages/acompanhamento/AcompanhamentoPage';

const navLinkClass = ({ isActive }: { isActive: boolean }) =>
  `px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
    isActive ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-muted hover:text-foreground'
  }`;

const mobileNavLinkClass = ({ isActive }: { isActive: boolean }) =>
  `block px-3 py-2 rounded-md text-sm font-medium transition-colors ${
    isActive ? 'bg-primary text-primary-foreground' : 'text-muted-foreground hover:bg-muted hover:text-foreground'
  }`;

type NavLinkClassFn = (props: { isActive: boolean }) => string;

function NavLinks({
  className,
  linkClass,
  onClick,
}: {
  className?: string;
  linkClass: NavLinkClassFn;
  onClick?: () => void;
}) {
  return (
    <nav className={className}>
      <NavLink to="/" end className={linkClass} onClick={onClick}>
        A semana
      </NavLink>
      <NavLink to="/acompanhamento" className={linkClass} onClick={onClick}>
        Acompanhamento
      </NavLink>
      <NavLink to="/perguntar" className={linkClass} onClick={onClick}>
        Perguntar
      </NavLink>
    </nav>
  );
}

function Layout() {
  const isMobile = useIsMobile();
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  // O template original sincronizava este estado com um useEffect
  // (`if (!isMobile) setMobileNavOpen(false)`), o que a regra
  // react-hooks/set-state-in-effect reprova -- com razao: e um render a mais
  // para chegar no mesmo lugar. Renderizando o Sheet SO no mobile, ele
  // desmonta ao passar para desktop e leva o estado junto. Nada a sincronizar.
  return (
    <div className="min-h-screen bg-background flex flex-col">
      <header className="border-b px-4 md:px-6 py-3 flex items-center gap-4">
        <h1 className="text-lg font-semibold text-foreground">Rota Perfume · Direção</h1>
        <NavLinks className="hidden md:flex gap-1" linkClass={navLinkClass} />
        {isMobile ? (
          <div className="ml-auto">
            <Sheet open={mobileNavOpen} onOpenChange={setMobileNavOpen}>
              <Button variant="ghost" size="icon" onClick={() => setMobileNavOpen(true)}>
                <Menu className="h-5 w-5" />
                <span className="sr-only">Abrir navegação</span>
              </Button>
              <SheetContent side="left">
                <SheetHeader>
                  <SheetTitle>Navegação</SheetTitle>
                </SheetHeader>
                <NavLinks
                  className="flex flex-col gap-1"
                  linkClass={mobileNavLinkClass}
                  onClick={() => setMobileNavOpen(false)}
                />
              </SheetContent>
            </Sheet>
          </div>
        ) : null}
      </header>

      <main className="flex-1 p-4 md:p-6">
        <Outlet />
      </main>
    </div>
  );
}

const router = createBrowserRouter([
  {
    element: <Layout />,
    children: [
      { path: '/', element: <SemanaPage /> },
      { path: '/acompanhamento', element: <AcompanhamentoPage /> },
      { path: '/perguntar', element: <PerguntarPage /> },
    ],
  },
]);

export default function App() {
  return <RouterProvider router={router} />;
}

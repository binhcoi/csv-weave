import { AppShell, Burger, Group, NavLink, Text, ThemeIcon, useMantineTheme } from '@mantine/core'
import { useDisclosure } from '@mantine/hooks'
import { logoGradient } from './themes'
import {
  IconArrowsExchange,
  IconFiles,
  IconHelp,
  IconTable,
  IconTransform,
} from '@tabler/icons-react'
import { NavLink as RouterNavLink, Outlet, useLocation } from 'react-router'

const navItems = [
  { to: '/file-types', label: 'File types', icon: IconTable },
  { to: '/maps', label: 'Transformation maps', icon: IconArrowsExchange },
  { to: '/files', label: 'Files and runs', icon: IconFiles },
  { to: '/help', label: 'Help', icon: IconHelp },
]

function AppLayout() {
  const [navOpened, { toggle, close }] = useDisclosure(false)
  const { pathname } = useLocation()
  const theme = useMantineTheme()

  return (
    <AppShell
      header={{ height: 56 }}
      navbar={{ width: 240, breakpoint: 'sm', collapsed: { mobile: !navOpened } }}
      padding="lg"
    >
      <AppShell.Header>
        <Group h="100%" px="md" gap="sm">
          <Burger
            opened={navOpened}
            onClick={toggle}
            hiddenFrom="sm"
            size="sm"
            aria-label="Toggle navigation"
          />
          <ThemeIcon variant="gradient" gradient={logoGradient(theme)} radius="md">
            <IconTransform size={18} />
          </ThemeIcon>
          <Text fw={700} fz="lg">
            CSVWeave
          </Text>
        </Group>
      </AppShell.Header>
      <AppShell.Navbar p="sm">
        <nav aria-label="Main navigation">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              component={RouterNavLink}
              to={item.to}
              label={item.label}
              leftSection={<item.icon size={18} stroke={1.6} />}
              active={pathname.startsWith(item.to)}
              onClick={close}
            />
          ))}
        </nav>
      </AppShell.Navbar>
      <AppShell.Main>
        <Outlet />
      </AppShell.Main>
    </AppShell>
  )
}

export default AppLayout

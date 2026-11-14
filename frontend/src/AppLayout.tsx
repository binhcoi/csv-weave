import {
  AppShell,
  Box,
  Burger,
  Button,
  Container,
  Group,
  NavLink,
  Text,
  ThemeIcon,
  UnstyledButton,
  useMantineTheme,
} from '@mantine/core'
import { useDisclosure } from '@mantine/hooks'
import {
  IconArrowsExchange,
  IconFiles,
  IconHelp,
  IconTable,
  IconTransform,
} from '@tabler/icons-react'
import { NavLink as RouterNavLink, Outlet, useLocation } from 'react-router'
import { logoGradient, useStylePreset } from './themes'

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
  const { nav, headerStyle, contentWidth, density } = useStylePreset().layout

  const sidebar = nav === 'sidebar' || nav === 'sidebar-compact'
  const filled = headerStyle === 'filled'
  const isActive = (to: string) => pathname.startsWith(to)

  // Used as the desktop sidebar in sidebar modes and as the mobile drawer in all modes.
  const sidebarLinks = (
    <nav aria-label="Main navigation">
      {navItems.map((item) => (
        <NavLink
          key={item.to}
          component={RouterNavLink}
          to={item.to}
          label={item.label}
          leftSection={<item.icon size={nav === 'sidebar' ? 18 : 16} stroke={1.6} />}
          active={isActive(item.to)}
          onClick={close}
        />
      ))}
    </nav>
  )

  const headerNav =
    nav === 'topbar-pills' || nav === 'topbar-text' ? (
      <Group
        component="nav"
        aria-label="Main navigation"
        gap={nav === 'topbar-text' ? 'xs' : 4}
        visibleFrom="sm"
        wrap="nowrap"
      >
        {navItems.map((item) => {
          const active = isActive(item.to)
          if (nav === 'topbar-text') {
            // Terminal style: plain text commands, inverted when active.
            return (
              <Button
                key={item.to}
                component={RouterNavLink}
                to={item.to}
                variant={active ? 'filled' : 'subtle'}
                color={active ? undefined : 'gray'}
                size="compact-sm"
              >
                {item.label}
              </Button>
            )
          }
          return (
            <Button
              key={item.to}
              component={RouterNavLink}
              to={item.to}
              variant={active ? 'light' : 'subtle'}
              color={active ? undefined : 'gray'}
              size="sm"
              leftSection={<item.icon size={16} stroke={1.6} />}
            >
              {item.label}
            </Button>
          )
        })}
      </Group>
    ) : null

  // Inkwell style: a second header row with underlined text tabs.
  const headerTabs =
    nav === 'header-tabs' ? (
      <Group
        component="nav"
        aria-label="Main navigation"
        justify="center"
        gap="xl"
        visibleFrom="sm"
        px="md"
        h={40}
      >
        {navItems.map((item) => {
          const active = isActive(item.to)
          return (
            <UnstyledButton
              key={item.to}
              component={RouterNavLink}
              to={item.to}
              fz="sm"
              fw={active ? 700 : 400}
              h="100%"
              style={{
                borderBottom: active
                  ? '2px solid var(--mantine-primary-color-filled)'
                  : '2px solid transparent',
              }}
            >
              {item.label}
            </UnstyledButton>
          )
        })}
      </Group>
    ) : null

  const content = <Outlet />

  return (
    <AppShell
      // The tabs row only shows from `sm` up, so the extra height is also responsive.
      header={{ height: nav === 'header-tabs' ? { base: 56, sm: 96 } : 56 }}
      navbar={{
        width: nav === 'sidebar' ? 240 : 200,
        breakpoint: 'sm',
        // Outside the sidebar modes, the navbar only serves as the mobile drawer.
        collapsed: { mobile: !navOpened, desktop: !sidebar },
      }}
      padding={density === 'airy' ? 'xl' : density === 'compact' ? 'md' : 'lg'}
    >
      <AppShell.Header
        bg={filled ? 'var(--mantine-primary-color-filled)' : undefined}
        c={filled ? 'var(--mantine-color-white)' : undefined}
      >
        <Group h={56} px="md" gap="sm" justify="space-between" wrap="nowrap">
          <Group gap="sm" wrap="nowrap">
            <Burger
              opened={navOpened}
              onClick={toggle}
              hiddenFrom="sm"
              size="sm"
              aria-label="Toggle navigation"
              color={filled ? 'var(--mantine-color-white)' : undefined}
            />
            <ThemeIcon
              variant={filled ? 'white' : 'gradient'}
              gradient={filled ? undefined : logoGradient(theme)}
              radius="md"
            >
              <IconTransform size={18} />
            </ThemeIcon>
            <Text fw={700} fz="lg">
              CSVWeave
            </Text>
          </Group>
          {headerNav}
        </Group>
        {headerTabs && <Box>{headerTabs}</Box>}
      </AppShell.Header>
      <AppShell.Navbar p={nav === 'sidebar' ? 'sm' : 'xs'}>{sidebarLinks}</AppShell.Navbar>
      <AppShell.Main>
        {contentWidth === 'full' ? (
          content
        ) : (
          <Container size={contentWidth === 'wide' ? 'lg' : 'sm'} px={0}>
            {content}
          </Container>
        )}
      </AppShell.Main>
    </AppShell>
  )
}

export default AppLayout

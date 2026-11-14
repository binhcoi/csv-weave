import { Anchor, Stack, Text, Title } from '@mantine/core'
import { useDocumentTitle } from '@mantine/hooks'
import { Link } from 'react-router'

function NotFoundPage() {
  useDocumentTitle('Page not found · CSVWeave')

  return (
    <Stack gap="sm">
      <Title order={1}>Page not found</Title>
      <Text>
        There is nothing at this address.{' '}
        <Anchor component={Link} to="/help">
          Go to the help page.
        </Anchor>
      </Text>
    </Stack>
  )
}

export default NotFoundPage

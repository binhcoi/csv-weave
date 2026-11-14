import { Badge, Button, Card, Group, SimpleGrid, Stack, Text, Title } from '@mantine/core'
import { useDocumentTitle } from '@mantine/hooks'
import { IconArrowRight, IconPlus } from '@tabler/icons-react'
import PreviewNote from '../components/PreviewNote'

const exampleMaps = [
  {
    name: 'Legacy customers to CRM',
    source: 'Customer import',
    target: 'CRM contacts',
    transformations: 6,
    unmapped: 0,
    description: 'Splits the combined name column and normalizes phone numbers.',
  },
  {
    name: 'Order lines to ledger',
    source: 'Order lines',
    target: 'Ledger entries',
    transformations: 9,
    unmapped: 2,
    description: 'Parses cent amounts into decimals and derives the booking date.',
  },
]

function MapsPage() {
  useDocumentTitle('Transformation maps · CSVWeave')

  return (
    <Stack gap="lg">
      <Group justify="space-between" align="center">
        <Title order={1}>Transformation maps</Title>
        <Button leftSection={<IconPlus size={16} />} disabled>
          New map
        </Button>
      </Group>
      <Text c="dimmed" maw="42rem">
        A map converts one file type into another. Each transformation fills a destination column
        from one or more source columns; destination columns may stay unmapped.
      </Text>
      <PreviewNote>
        Example data to settle the look and feel. Creating and editing maps arrives with the map
        editor milestone.
      </PreviewNote>
      <SimpleGrid cols={{ base: 1, md: 2 }}>
        {exampleMaps.map((map) => (
          <Card key={map.name} withBorder>
            <Stack gap="xs">
              <Text fw={600}>{map.name}</Text>
              <Group gap="xs">
                <Badge variant="default">{map.source}</Badge>
                <IconArrowRight size={16} aria-label="to" />
                <Badge variant="default">{map.target}</Badge>
              </Group>
              <Text size="sm" c="dimmed">
                {map.description}
              </Text>
              <Group gap="xs">
                <Badge variant="light">{map.transformations} transformations</Badge>
                {map.unmapped > 0 && (
                  <Badge variant="light" color="yellow">
                    {map.unmapped} unmapped
                  </Badge>
                )}
              </Group>
            </Stack>
          </Card>
        ))}
      </SimpleGrid>
    </Stack>
  )
}

export default MapsPage

import { Badge, Button, Group, Stack, Text, Title } from '@mantine/core'
import { useDocumentTitle } from '@mantine/hooks'
import { IconArrowRight, IconPlus } from '@tabler/icons-react'
import Collection, { type CollectionField } from '../components/Collection'
import PreviewNote from '../components/PreviewNote'

interface ExampleMap {
  name: string
  source: string
  target: string
  transformations: number
  unmapped: number
  description: string
}

const exampleMaps: ExampleMap[] = [
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

const fields: CollectionField<ExampleMap>[] = [
  { key: 'name', label: 'Name', render: (map) => map.name },
  {
    key: 'route',
    label: 'Converts',
    render: (map) => (
      <Group gap="xs" wrap="nowrap">
        <Badge variant="default">{map.source}</Badge>
        <IconArrowRight size={14} aria-label="to" />
        <Badge variant="default">{map.target}</Badge>
      </Group>
    ),
  },
  { key: 'description', label: 'Description', render: (map) => map.description },
  {
    key: 'transformations',
    label: 'Transformations',
    render: (map) => (
      <Group gap="xs">
        <Badge variant="light">{map.transformations}</Badge>
        {map.unmapped > 0 && (
          <Badge variant="light" color="yellow">
            {map.unmapped} unmapped
          </Badge>
        )}
      </Group>
    ),
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
      <Collection items={exampleMaps} fields={fields} itemKey={(map) => map.name} />
    </Stack>
  )
}

export default MapsPage
